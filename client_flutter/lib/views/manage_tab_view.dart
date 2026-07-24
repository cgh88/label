import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/api_sync_service.dart';

class ManageTabView extends StatefulWidget {
  final String userRole;

  const ManageTabView({super.key, required this.userRole});

  @override
  State<ManageTabView> createState() => _ManageTabViewState();
}

class _ManageTabViewState extends State<ManageTabView> {
  final _newCategoryController = TextEditingController();
  final _newCategoryEmojiController = TextEditingController();
  final _newLocationController = TextEditingController();
  final _searchController = TextEditingController();

  String _searchQuery = '';
  int? _sortColumnIndex;
  bool _sortAscending = true;

  bool _isSyncing = false;
  String _syncStatus = '대기 중';
  Color _syncStatusColor = Colors.white70;

  @override
  void initState() {
    super.initState();
    _checkSyncStatus();
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    _newCategoryEmojiController.dispose();
    _newLocationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Ingredient> _getFilteredAndSortedIngredients() {
    final list = DatabaseService.instance.ingredients.where((ing) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return ing.category.toLowerCase().contains(q) ||
             ing.name.toLowerCase().contains(q) ||
             ing.abbr.toLowerCase().contains(q);
    }).toList();

    if (_sortColumnIndex != null) {
      list.sort((a, b) {
        int cmp = 0;
        if (_sortColumnIndex == 0) {
          cmp = a.category.compareTo(b.category);
        } else if (_sortColumnIndex == 1) {
          cmp = a.name.compareTo(b.name);
        } else if (_sortColumnIndex == 2) {
          cmp = a.abbr.compareTo(b.abbr);
        }
        return _sortAscending ? cmp : -cmp;
      });
    }

    return list;
  }

  Future<void> _checkSyncStatus() async {
    if (!ApiSyncService.instance.isConfigured()) {
      setState(() {
        _syncStatus = '동기화 API 주소가 설정되지 않았습니다.';
        _syncStatusColor = Colors.orangeAccent;
      });
      return;
    }
    setState(() {
      _syncStatus = '동기화 주소: ${ApiSyncService.instance.apiSyncUrl}';
      _syncStatusColor = Colors.blueAccent;
    });
  }

  Future<void> _runApiSync() async {
    if (!ApiSyncService.instance.isConfigured()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정 탭에서 API 동기화 주소를 먼저 구성해 주세요.')),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStatus = '서버 동기화 중...';
      _syncStatusColor = Colors.amberAccent;
    });

    final result = await ApiSyncService.instance.performSync();

    setState(() {
      _isSyncing = false;
      _syncStatus = result.message;
      _syncStatusColor = result.success ? Colors.greenAccent : Colors.redAccent;
    });

    if (result.success) {
      // Reload local data
      setState(() {});
    }
  }

  // --- Category Operations ---
  void _addCategory() {
    if (widget.userRole != 'admin') return;
    final name = _newCategoryController.text.trim();
    final emoji = _newCategoryEmojiController.text.trim();
    if (name.isEmpty) return;

    if (DatabaseService.instance.categories.any((c) => c.name == name)) {
      _showError('이미 존재하는 카테고리입니다.');
      return;
    }

    final newId = DatabaseService.instance.categories.fold<int>(0, (max, c) => c.id > max ? c.id : max) + 1;
    final newSortOrder = DatabaseService.instance.categories.fold<int>(0, (max, c) => c.sortOrder > max ? c.sortOrder : max) + 1;

    setState(() {
      DatabaseService.instance.categories.add(
        AppCategory(id: newId, name: name, emoji: emoji.isEmpty ? '🍕' : emoji, sortOrder: newSortOrder),
      );
      _newCategoryController.clear();
      _newCategoryEmojiController.clear();
    });
    DatabaseService.instance.save();
    _checkSyncStatus();
  }

  void _deleteCategory(int id) {
    if (widget.userRole != 'admin') return;
    setState(() {
      DatabaseService.instance.categories.removeWhere((c) => c.id == id);
    });
    DatabaseService.instance.save();
    _checkSyncStatus();
  }

  // --- Location Operations ---
  void _addLocation() {
    if (widget.userRole != 'admin') return;
    final name = _newLocationController.text.trim();
    if (name.isEmpty) return;

    if (DatabaseService.instance.locations.any((l) => l.name == name)) {
      _showError('이미 존재하는 보관위치입니다.');
      return;
    }

    final newId = DatabaseService.instance.locations.fold<int>(0, (max, l) => l.id > max ? l.id : max) + 1;
    final newSortOrder = DatabaseService.instance.locations.fold<int>(0, (max, l) => l.sortOrder > max ? l.sortOrder : max) + 1;

    setState(() {
      DatabaseService.instance.locations.add(
        StorageLocation(id: newId, name: name, sortOrder: newSortOrder),
      );
      _newLocationController.clear();
    });
    DatabaseService.instance.save();
    _checkSyncStatus();
  }

  void _deleteLocation(int id) {
    if (widget.userRole != 'admin') return;
    setState(() {
      DatabaseService.instance.locations.removeWhere((l) => l.id == id);
      // Cascading delete mapping limits
      for (var ing in DatabaseService.instance.ingredients) {
        final loc = DatabaseService.instance.locations.firstWhere((element) => element.id == id, orElse: () => StorageLocation(id: -1, name: '', sortOrder: 0));
        if (loc.id != -1) {
          ing.storage.remove(loc.name);
        }
      }
    });
    DatabaseService.instance.save();
    _checkSyncStatus();
  }

  // --- Ingredient Add/Edit Dialogs ---
  void _showAddEditIngredientDialog([Ingredient? ingredient]) {
    if (widget.userRole != 'admin') return;
    
    final nameController = TextEditingController(text: ingredient?.name ?? '');
    final abbrController = TextEditingController(text: ingredient?.abbr ?? '');
    String selectedCategory = ingredient?.category ??
        (DatabaseService.instance.categories.isNotEmpty ? DatabaseService.instance.categories.first.name : '');

    // Map to hold shelf limits: key storage location name -> text controller
    final limitControllers = <String, TextEditingController>{};
    for (var loc in DatabaseService.instance.locations) {
      final initialVal = ingredient?.storage[loc.name]?.days.toString() ?? '';
      limitControllers[loc.name] = TextEditingController(text: initialVal);
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1936),
          title: Text(
            ingredient == null ? '재료 추가' : '재료 수정',
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedCategory.isEmpty ? null : selectedCategory,
                    dropdownColor: const Color(0xFF1C1936),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '카테고리',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    items: DatabaseService.instance.categories.map((c) {
                      return DropdownMenuItem<String>(
                        value: c.name,
                        child: Text('${c.emoji} ${c.name}'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedCategory = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    enabled: ingredient == null, // Name is primary key, cannot edit
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '재료명',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: abbrController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '인쇄 약어',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '보관 규정 (시간/일 입력)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '* 분할/소스보틀: 시간 단위 입력 (예: 24)\n* 해동/메이크라인/랙산: 일 단위 입력 (예: 7)',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ...DatabaseService.instance.locations.map((loc) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              loc.name,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: limitControllers[loc.name],
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                hintText: '비워둠 (보관 안함)',
                                hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
              onPressed: () {
                final name = nameController.text.trim();
                final abbr = abbrController.text.trim();
                if (name.isEmpty || selectedCategory.isEmpty) return;

                if (ingredient == null &&
                    DatabaseService.instance.ingredients.any((i) => i.name.toLowerCase() == name.toLowerCase())) {
                  _showError('이미 존재하는 재료입니다.');
                  return;
                }

                final storageLimits = <String, IngredientStorageLimit>{};
                limitControllers.forEach((locName, ctrl) {
                  final limitText = ctrl.text.trim();
                  if (limitText.isNotEmpty) {
                    final val = int.tryParse(limitText);
                    final locObj = DatabaseService.instance.locations.firstWhere((l) => l.name == locName);
                    if (val != null) {
                      storageLimits[locName] = IngredientStorageLimit(id: locObj.id, days: val);
                    }
                  }
                });

                setState(() {
                  if (ingredient == null) {
                    DatabaseService.instance.ingredients.add(
                      Ingredient(
                        name: name,
                        category: selectedCategory,
                        abbr: abbr,
                        storage: storageLimits,
                      ),
                    );
                  } else {
                    final idx = DatabaseService.instance.ingredients.indexWhere((i) => i.name == ingredient.name);
                    if (idx != -1) {
                      DatabaseService.instance.ingredients[idx] = Ingredient(
                        name: ingredient.name,
                        category: selectedCategory,
                        abbr: abbr,
                        storage: storageLimits,
                      );
                    }
                  }
                });

                DatabaseService.instance.save();
                _checkSyncStatus();
                Navigator.of(context).pop();
              },
              child: Text(ingredient == null ? '추가' : '수정', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteIngredient(Ingredient ing) {
    if (widget.userRole != 'admin') return;
    setState(() {
      DatabaseService.instance.ingredients.removeWhere((i) => i.name == ing.name);
    });
    DatabaseService.instance.save();
    _checkSyncStatus();
  }

  Future<void> _resetToDefaults() async {
    if (widget.userRole != 'admin') return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1936),
        title: const Text('초기화 확인', style: TextStyle(color: Colors.white)),
        content: const Text(
          '모든 재료와 보관 기준을 기본값으로 복원하시겠습니까? 로컬 변경사항은 모두 삭제됩니다.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('초기화 실행', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      double progressValue = 0.0;
      bool isIndeterminate = false;
      StateSetter? dialogSetState;

      // Show download progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              dialogSetState = setDialogState;
              return AlertDialog(
                backgroundColor: const Color(0xFF1C1936),
                title: const Text('기본 데이터베이스 다운로드', style: TextStyle(color: Colors.white, fontSize: 16)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isIndeterminate
                          ? '서버에서 기본 데이터를 받는 중...'
                          : '다운로드 중: ${(progressValue * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: isIndeterminate ? null : progressValue,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C4DFF)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

      try {
        final apiBaseUrl = ApiSyncService.instance.isConfigured()
            ? ApiSyncService.instance.apiSyncUrl
            : 'http://localhost:3000';
        await DatabaseService.instance.downloadAndResetDatabase(
          url: '$apiBaseUrl/api/default-database',
          onProgress: (progress) {
            if (dialogSetState != null) {
              dialogSetState!(() {
                if (progress < 0) {
                  isIndeterminate = true;
                } else {
                  isIndeterminate = false;
                  progressValue = progress;
                }
              });
            }
          },
        );

        if (mounted) Navigator.of(context).pop(); // Close progress dialog

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('서버로부터 기본 데이터를 다운로드하여 복원했습니다.', style: TextStyle(color: Colors.white)),
            ),
          );
        }
      } catch (e) {
        if (mounted) Navigator.of(context).pop(); // Close progress dialog

        if (mounted) {
          final useFallback = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1C1936),
              title: const Text('다운로드 실패', style: TextStyle(color: Colors.white)),
              content: Text(
                '서버 연결에 실패했습니다: $e\n\n앱에 내장된 기본 데이터 파일로 대신 복원하시겠습니까?',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('취소', style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('내장 데이터로 복원', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (useFallback == true) {
            await DatabaseService.instance.resetToDefaults();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Colors.blueAccent,
                  content: Text('내장된 기본 데이터로 복원 완료했습니다.', style: TextStyle(color: Colors.white)),
                ),
              );
            }
          }
        }
      }

      setState(() {});
      _checkSyncStatus();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.redAccent,
      content: Text(msg, style: const TextStyle(color: Colors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.userRole == 'admin';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SSH Sync Header Card
            Card(
              color: isDark ? const Color(0xFF1E2030) : Colors.white,
              elevation: 3,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: const Color(0xFFFF1E1E).withOpacity(0.4), width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '서버 데이터베이스 동기화',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text('동기화 상태: ', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13)),
                              Text(
                                _syncStatus,
                                style: TextStyle(color: _syncStatusColor, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '마지막 로컬 업데이트: ${DatabaseService.instance.lastUpdated}',
                            style: TextStyle(color: isDark ? Colors.white.withOpacity(0.5) : Colors.black45, fontSize: 11),
                          )
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isSyncing ? null : _runApiSync,
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                            )
                          : const Icon(Icons.sync),
                      label: const Text('동기화 실행'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF1E1E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Top Layout: Categories and Locations Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category Card
                Expanded(
                  child: Card(
                    color: isDark ? const Color(0xFF1E2030) : Colors.white,
                    elevation: 3,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: isDark ? Colors.white.withOpacity(0.18) : const Color(0xFFCBD5E1), width: 1.2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '카테고리 관리',
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: DatabaseService.instance.categories.map((c) {
                              return Chip(
                                label: Text('${c.emoji} ${c.name}'),
                                backgroundColor: isDark ? const Color(0xFF2B2D42) : const Color(0xFFF1F5F9),
                                labelStyle: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 13, fontWeight: FontWeight.bold),
                                deleteIconColor: Colors.redAccent,
                                onDeleted: isAdmin ? () => _deleteCategory(c.id) : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFCBD5E1)),
                                ),
                              );
                            }).toList(),
                          ),
                          if (isAdmin) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                SizedBox(
                                  width: 60,
                                  child: TextField(
                                    controller: _newCategoryEmojiController,
                                    decoration: InputDecoration(
                                      hintText: '이모지',
                                      hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 12),
                                    ),
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _newCategoryController,
                                    decoration: InputDecoration(
                                      hintText: '새 카테고리명',
                                      hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 12),
                                    ),
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, color: Color(0xFF6366F1)),
                                  onPressed: _addCategory,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Location Card
                Expanded(
                  child: Card(
                    color: isDark ? const Color(0xFF1E2030) : Colors.white,
                    elevation: 3,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: isDark ? Colors.white.withOpacity(0.18) : const Color(0xFFCBD5E1), width: 1.2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '보관위치 관리',
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: DatabaseService.instance.locations.map((l) {
                              return Chip(
                                label: Text(l.name),
                                backgroundColor: isDark ? const Color(0xFF2B2D42) : const Color(0xFFF1F5F9),
                                labelStyle: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 13, fontWeight: FontWeight.bold),
                                deleteIconColor: Colors.redAccent,
                                onDeleted: isAdmin ? () => _deleteLocation(l.id) : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFCBD5E1)),
                                ),
                              );
                            }).toList(),
                          ),
                          if (isAdmin) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _newLocationController,
                                    decoration: InputDecoration(
                                      hintText: '새 보관위치명',
                                      hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 12),
                                    ),
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, color: Color(0xFF6366F1)),
                                  onPressed: _addLocation,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Ingredients List Management Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '등록 재료 목록',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (isAdmin)
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _resetToDefaults,
                        icon: const Icon(Icons.refresh),
                        label: const Text('기본값 복원'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[800],
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => _showAddEditIngredientDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('재료 등록'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Search Bar
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: '카테고리, 재료명 또는 약어로 검색...',
                  hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: isDark ? Colors.white54 : Colors.black54, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: isDark ? Colors.white54 : Colors.black54, size: 18),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E2030) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.18) : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.18) : const Color(0xFFCBD5E1), width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFFF1E1E), width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Ingredients DataTable Card
            Card(
              color: isDark ? const Color(0xFF1E2030) : Colors.white,
              elevation: 3,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: isDark ? Colors.white.withOpacity(0.18) : const Color(0xFFCBD5E1), width: 1.2),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  columns: [
                    DataColumn(
                      label: Text('카테고리', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold)),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    DataColumn(
                      label: Text('재료명', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold)),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    DataColumn(
                      label: Text('약어', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold)),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    DataColumn(label: Text('보관 규정 기준', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('관리', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold))),
                  ],
                  rows: _getFilteredAndSortedIngredients().map((ing) {
                    final limitsText = ing.storage.entries.map((e) {
                      final unit = (e.key == '분할' || e.key == '소스보틀') ? '시간' : '일';
                      return '${e.key}: ${e.value.days}$unit';
                    }).join(', ');

                    return DataRow(
                      cells: [
                        DataCell(Text(ing.category, style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                        DataCell(Text(ing.name, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold))),
                        DataCell(Text(ing.abbr, style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold))),
                        DataCell(Text(limitsText.isEmpty ? '미정' : limitsText, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 18),
                                onPressed: isAdmin ? () => _showAddEditIngredientDialog(ing) : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                onPressed: isAdmin ? () => _deleteIngredient(ing) : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
