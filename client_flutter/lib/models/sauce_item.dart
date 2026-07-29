class SauceItem {
  final String sourceId;
  String sauceCode; // 'PS', 'GD', 'BQ', 'HS'
  String status; // 'PREP', 'IN', 'OUT', 'DISCARD'
  DateTime prepTime;
  int totalValidMin;
  double accumUsedMin;
  double remValidMin;
  DateTime lastActionTime;
  DateTime? estDiscardTime;

  SauceItem({
    required this.sourceId,
    this.sauceCode = 'PS',
    required this.status,
    required this.prepTime,
    this.totalValidMin = 600,
    this.accumUsedMin = 0.0,
    this.remValidMin = 600.0,
    required this.lastActionTime,
    this.estDiscardTime,
  });

  /// Calculates dynamic remaining minutes based on current system time
  double getDynamicRemainingMin(DateTime now) {
    if (status == 'DISCARD') return 0.0;
    if (status == 'IN') return remValidMin;

    // For PREP or OUT, time is counting down from lastActionTime
    double elapsedMin = 0.0;
    if (now.isAfter(lastActionTime)) {
      elapsedMin = now.difference(lastActionTime).inMilliseconds / (1000.0 * 60.0);
    }
    double currentRem = totalValidMin - accumUsedMin - elapsedMin;
    return currentRem < 0.0 ? 0.0 : currentRem;
  }

  /// Calculates dynamic progress percentage (0.0 to 100.0)
  double getProgressPercentage(DateTime now) {
    if (status == 'DISCARD') return 0.0;
    final rem = getDynamicRemainingMin(now);
    return (rem / totalValidMin * 100.0).clamp(0.0, 100.0);
  }

  /// Updates status if expired given current time
  bool updateExpirationCheck(DateTime now) {
    if (status == 'DISCARD') return false;

    final currentRem = getDynamicRemainingMin(now);
    bool expired = currentRem <= 0.0;
    if (estDiscardTime != null && (now.isAfter(estDiscardTime!) || now.isAtSameMomentAs(estDiscardTime!))) {
      expired = true;
    }

    if (expired) {
      status = 'DISCARD';
      remValidMin = 0.0;
      accumUsedMin = totalValidMin.toDouble();
      estDiscardTime = now;
      return true; // status changed
    }
    return false;
  }

  /// Trigger PREP action
  static SauceItem createPrep({
    required String sourceId,
    String sauceCode = 'PS',
    int totalValidMin = 600,
    required DateTime now,
  }) {
    final estDiscard = now.add(Duration(minutes: totalValidMin));
    return SauceItem(
      sourceId: sourceId,
      sauceCode: sauceCode,
      status: 'PREP',
      prepTime: now,
      totalValidMin: totalValidMin,
      accumUsedMin: 0.0,
      remValidMin: totalValidMin.toDouble(),
      lastActionTime: now,
      estDiscardTime: estDiscard,
    );
  }

  /// Trigger IN action (Store in fridge / Pause countdown)
  void triggerIn(DateTime now) {
    if (status == 'DISCARD' || status == 'IN') return;

    double workDuration = 0.0;
    if (now.isAfter(lastActionTime)) {
      workDuration = now.difference(lastActionTime).inMilliseconds / (1000.0 * 60.0);
    }

    accumUsedMin = (accumUsedMin + workDuration).clamp(0.0, totalValidMin.toDouble());
    remValidMin = (totalValidMin - accumUsedMin).clamp(0.0, totalValidMin.toDouble());
    lastActionTime = now;
    estDiscardTime = null; // Paused in fridge
    status = 'IN';
  }

  /// Trigger OUT action (Retrieve from fridge to room temp)
  void triggerOut(DateTime now, {int startHour = 11}) {
    if (status == 'DISCARD' || status == 'PREP' || status == 'OUT') return;

    // Rule: If retrieved before operating start hour (e.g. 11:00 AM) today, countdown starts at 11:00 AM
    final openTimeToday = DateTime(now.year, now.month, now.day, startHour, 0, 0);

    DateTime effectiveStart = now;
    if (now.isBefore(openTimeToday)) {
      effectiveStart = openTimeToday;
    }

    lastActionTime = effectiveStart;
    estDiscardTime = effectiveStart.add(Duration(minutes: remValidMin.round()));
    status = 'OUT';
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceId': sourceId,
      'source_id': sourceId,
      'sauceCode': sauceCode,
      'sauce_code': sauceCode,
      'status': status,
      'prepTime': prepTime.toIso8601String(),
      'prep_time': prepTime.toIso8601String(),
      'totalValidMin': totalValidMin,
      'total_valid_min': totalValidMin,
      'accumUsedMin': accumUsedMin,
      'accum_used_min': accumUsedMin,
      'remValidMin': remValidMin,
      'rem_valid_min': remValidMin,
      'lastActionTime': lastActionTime.toIso8601String(),
      'last_action_time': lastActionTime.toIso8601String(),
      'estDiscardTime': estDiscardTime?.toIso8601String(),
      'est_discard_time': estDiscardTime?.toIso8601String(),
    };
  }

  factory SauceItem.fromJson(Map<String, dynamic> json) {
    final sId = json['source_id'] ?? json['sourceId'] ?? '';
    final sCode = json['sauce_code'] ?? json['sauceCode'] ?? 'PS';
    final st = json['status'] ?? 'PREP';
    final pTimeStr = json['prep_time'] ?? json['prepTime'] ?? DateTime.now().toIso8601String();
    final totMin = (json['total_valid_min'] ?? json['totalValidMin'] as num?)?.toInt() ?? 600;
    final accMin = (json['accum_used_min'] ?? json['accumUsedMin'] as num?)?.toDouble() ?? 0.0;
    final remMin = (json['rem_valid_min'] ?? json['remValidMin'] as num?)?.toDouble() ?? totMin.toDouble();
    final lastActStr = json['last_action_time'] ?? json['lastActionTime'] ?? pTimeStr;
    final estDiscStr = json['est_discard_time'] ?? json['estDiscardTime'];

    return SauceItem(
      sourceId: sId,
      sauceCode: sCode,
      status: st,
      prepTime: DateTime.parse(pTimeStr),
      totalValidMin: totMin,
      accumUsedMin: accMin,
      remValidMin: remMin,
      lastActionTime: DateTime.parse(lastActStr),
      estDiscardTime: estDiscStr != null ? DateTime.parse(estDiscStr) : null,
    );
  }
}
