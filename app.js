// ==========================================
// Server DB API Wrapper & Helper
// ==========================================
async function apiGet(url) {
    const response = await fetch(url);
    if (!response.ok) throw new Error("데이터 조회 실패");
    return await response.json();
}

async function apiPost(url, data) {
    const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data)
    });
    if (!response.ok) {
        const err = await response.json();
        throw new Error(err.error || "요청 처리 실패");
    }
    return await response.json();
}

async function apiDelete(url) {
    const response = await fetch(url, { method: "DELETE" });
    if (!response.ok) {
        const err = await response.json();
        throw new Error(err.error || "삭제 실패");
    }
    return await response.json();
}

// ==========================================
// App State
// ==========================================
let state = {
    ingredients: [],
    categories: [],
    locations: [],
    presets: [],
    selectedId: null,      // Name string of selected ingredient
    selectedStorage: null, // Name of selected storage location (e.g. "워크인 랙산")
    prepTime: null,        // Date Object
    staffName: "",
    printQty: 1,
    theme: "dark",
    activeTab: "tab-print",
    filters: {
        category: "all",
        search: ""
    }
};

// ==========================================
// DOM Cache (Static elements)
// ==========================================
const ingredientsGrid = document.getElementById("ingredients-grid");
const searchInput = document.getElementById("ingredient-search");

const selectedIngDisplay = document.getElementById("selected-ingredient-display");
const storageOptionsContainer = document.getElementById("storage-options");
const prepTimeInput = document.getElementById("prep-time-input");
const staffInput = document.getElementById("staff-input");
const labelQtyInput = document.getElementById("label-qty");

// Preview Elements
const stickerName = document.getElementById("sticker-name");
const stickerAbbr = document.getElementById("sticker-abbr");
const stickerLoc = document.getElementById("sticker-loc");
const stickerPrepDate = document.getElementById("sticker-prep-date");
const stickerExpireDate = document.getElementById("sticker-expire-date");
const stickerStaffVal = document.getElementById("sticker-staff-val");

// Control buttons
const printLabelBtn = document.getElementById("print-label-btn");
const themeToggleBtn = document.getElementById("theme-toggle-btn");
const printStickerContainer = document.getElementById("print-sticker-container");

// Modals
const settingsOpenBtn = document.getElementById("settings-open-btn");
const settingsCloseBtn = document.getElementById("settings-close-btn");
const settingsModal = document.getElementById("settings-modal");

// ==========================================
// Initialization & Event Binding
// ==========================================
document.addEventListener("DOMContentLoaded", async () => {
    initTheme();
    initDateTime();
    loadStaffName();
    
    try {
        await loadAllData();
    } catch (e) {
        console.error("Failed to load initial data from Server DB", e);
        alert("데이터베이스 연결에 실패했습니다.");
    }

    initTabs();
    initLabelSizeControls();
    setupEventHandlers();
    
    // Initial Render
    renderCategoryFilterTabs();
    renderIngredients();
    renderCategoryChips();
    renderLocationChips();
    renderCategoryDropdown();
    renderStorageFieldsInForm();
    renderRegisteredIngredientsTable();
    
    // Auto-select first ingredient
    if (state.ingredients.length > 0) {
        selectIngredient(state.ingredients[0].name);
    }
    
    lucide.createIcons();
});

// ==========================================
// Core States & CRUD Operations
// ==========================================
async function loadAllData() {
    state.ingredients = await apiGet("/api/ingredients");
    state.categories = await apiGet("/api/categories");
    state.locations = await apiGet("/api/storage-locations");
    state.presets = await apiGet("/api/label-sizes");
}

function initTabs() {
    const tabs = document.querySelectorAll(".main-tab");
    tabs.forEach(tab => {
        tab.addEventListener("click", () => {
            tabs.forEach(t => t.classList.remove("active"));
            tab.classList.add("active");
            
            const targetTab = tab.dataset.tab;
            state.activeTab = targetTab;
            
            document.querySelectorAll(".tab-content").forEach(content => {
                if (content.id === targetTab) {
                    content.classList.add("active");
                } else {
                    content.classList.remove("active");
                }
            });
            
            // Refresh logic based on tab
            if (targetTab === "tab-print") {
                renderCategoryFilterTabs();
                renderIngredients();
                if (state.selectedId) {
                    const ing = state.ingredients.find(i => i.name === state.selectedId);
                    if (ing) {
                        renderStorageOptions(ing);
                        updateStickerPreview();
                    }
                }
            } else if (targetTab === "tab-manage") {
                renderCategoryChips();
                renderLocationChips();
                renderCategoryDropdown();
                renderStorageFieldsInForm();
                renderRegisteredIngredientsTable();
            }
        });
    });
}

function initLabelSizeControls() {
    const labelWidthInput = document.getElementById("label-width");
    const labelHeightInput = document.getElementById("label-height");
    const savePresetBtn = document.getElementById("save-current-size-preset-btn");

    // Load saved sizes from localStorage
    const savedWidth = localStorage.getItem("label_width");
    const savedHeight = localStorage.getItem("label_height");

    if (savedWidth && savedHeight) {
        if (labelWidthInput) labelWidthInput.value = savedWidth;
        if (labelHeightInput) labelHeightInput.value = savedHeight;
    }

    if (labelWidthInput && labelHeightInput) {
        labelWidthInput.addEventListener("input", () => {
            updateLabelSize();
            saveLabelSize();
        });
        labelHeightInput.addEventListener("input", () => {
            updateLabelSize();
            saveLabelSize();
        });
    }

    if (savePresetBtn) {
        savePresetBtn.addEventListener("click", handleAddPreset);
    }

    renderPresetButtons();
    updateLabelSize();
}

function renderPresetButtons() {
    const container = document.getElementById("db-size-presets");
    if (!container) return;
    
    container.innerHTML = "";
    const labelWidthInput = document.getElementById("label-width");
    const labelHeightInput = document.getElementById("label-height");

    state.presets.forEach(p => {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "size-preset-btn";
        btn.dataset.w = p.width;
        btn.dataset.h = p.height;
        btn.dataset.id = p.id;
        const standardSizes = [[50,30], [60,40], [70,40], [80,50], [100,60], [100,70]];
        const isStandard = p.is_default === 1 || standardSizes.some(sz => sz[0] === p.width && sz[1] === p.height);
        const deleteBtnHTML = isStandard ? "" : `<span class="delete-preset-x" data-id="${p.id}">&times;</span>`;
        
        btn.innerHTML = `
            <span>${p.width}×${p.height}</span>
            ${deleteBtnHTML}
        `;
        if (!isStandard) {
            btn.classList.add("has-delete");
        }
        
        btn.addEventListener("click", (e) => {
            if (e.target.classList.contains("delete-preset-x")) return;
            
            document.querySelectorAll(".size-preset-btn").forEach(b => b.classList.remove("active"));
            btn.classList.add("active");
            
            if (labelWidthInput && labelHeightInput) {
                labelWidthInput.value = p.width;
                labelHeightInput.value = p.height;
            }
            updateLabelSize();
            saveLabelSize();
        });
        
        if (!isStandard) {
            btn.querySelector(".delete-preset-x").addEventListener("click", async (e) => {
                e.stopPropagation();
                if (confirm(`'${p.width}×${p.height}' 규격 프리셋을 삭제하시겠습니까?`)) {
                    try {
                        await apiDelete(`/api/label-sizes/${p.id}`);
                        state.presets = await apiGet("/api/label-sizes");
                        renderPresetButtons();
                        updateLabelSize();
                    } catch (err) {
                        alert("프리셋 삭제에 실패했습니다: " + err.message);
                    }
                }
            });
        }
        
        container.appendChild(btn);
    });
}

function updateLabelSize() {
    const labelWidthInput = document.getElementById("label-width");
    const labelHeightInput = document.getElementById("label-height");
    const previewSizeLabel = document.getElementById("preview-size-label");

    if (!labelWidthInput || !labelHeightInput) return;
    
    const w = parseFloat(labelWidthInput.value) || 50;
    const h = parseFloat(labelHeightInput.value) || 30;
    
    document.documentElement.style.setProperty("--label-w", w);
    document.documentElement.style.setProperty("--label-h", h);
    if (previewSizeLabel) {
        previewSizeLabel.textContent = `${w} × ${h}`;
    }

    // Match active class with selected preset
    document.querySelectorAll(".size-preset-btn").forEach(btn => {
        if (parseFloat(btn.dataset.w) === w && parseFloat(btn.dataset.h) === h) {
            btn.classList.add("active");
        } else {
            btn.classList.remove("active");
        }
    });
}

function saveLabelSize() {
    const labelWidthInput = document.getElementById("label-width");
    const labelHeightInput = document.getElementById("label-height");
    if (labelWidthInput && labelHeightInput) {
        localStorage.setItem("label_width", labelWidthInput.value);
        localStorage.setItem("label_height", labelHeightInput.value);
    }
}

async function handleAddPreset() {
    const labelWidthInput = document.getElementById("label-width");
    const labelHeightInput = document.getElementById("label-height");
    
    const w = parseInt(labelWidthInput.value);
    const h = parseInt(labelHeightInput.value);
    
    if (!w || !h) {
        alert("올바른 가로, 세로 크기를 입력해 주세요.");
        return;
    }
    if (w < 20 || w > 150 || h < 15 || h > 150) {
        alert("가로 크기는 20~150mm, 세로 크기는 15~150mm 사이여야 합니다.");
        return;
    }
    
    try {
        await apiPost("/api/label-sizes", { width: w, height: h });
        state.presets = await apiGet("/api/label-sizes");
        renderPresetButtons();
        updateLabelSize();
    } catch (err) {
        alert("규격 등록에 실패했습니다: " + err.message);
    }
}

function initDateTime() {
    state.prepTime = new Date();
    updatePrepTimeInputDisplay();
}

function updatePrepTimeInputDisplay() {
    const tzOffset = state.prepTime.getTimezoneOffset() * 60000;
    const localISOTime = (new Date(state.prepTime - tzOffset)).toISOString().slice(0, 16);
    prepTimeInput.value = localISOTime;
}

function loadStaffName() {
    const savedStaff = localStorage.getItem("label_staff_name");
    if (savedStaff) {
        state.staffName = savedStaff;
        staffInput.value = savedStaff;
        stickerStaffVal.textContent = savedStaff;
    }
}

function setupEventHandlers() {
    // Search
    searchInput.addEventListener("input", (e) => {
        state.filters.search = e.target.value.trim();
        renderIngredients();
    });
    
    // Theme Toggle
    themeToggleBtn.addEventListener("click", toggleTheme);
    
    // Prep Time Input Manual Change
    prepTimeInput.addEventListener("change", (e) => {
        if (e.target.value) {
            state.prepTime = new Date(e.target.value);
            updateStickerPreview();
        }
    });
    
    // Time adjustment buttons
    document.querySelectorAll(".time-adjust-btn").forEach(btn => {
        btn.addEventListener("click", (e) => {
            const action = e.target.closest("button").dataset.action;
            adjustPrepTime(action);
        });
    });
    
    // Staff Input
    staffInput.addEventListener("input", (e) => {
        state.staffName = e.target.value;
        localStorage.setItem("label_staff_name", state.staffName);
        updateStickerPreview();
    });
    
    // Qty input
    labelQtyInput.addEventListener("change", (e) => {
        state.printQty = parseInt(e.target.value) || 1;
    });
    
    // Print button
    printLabelBtn.addEventListener("click", triggerPrint);
    
    // Settings modal controls
    settingsOpenBtn.addEventListener("click", openSettingsModal);
    settingsCloseBtn.addEventListener("click", closeSettingsModal);
    settingsModal.addEventListener("click", (e) => {
        if (e.target === settingsModal) closeSettingsModal();
    });

    // Forms in Management Tab
    document.getElementById("add-category-form").addEventListener("submit", handleAddCategory);
    document.getElementById("add-location-form").addEventListener("submit", handleAddLocation);
    document.getElementById("mgmt-add-ingredient-form").addEventListener("submit", handleMgmtAddIngredient);
    document.getElementById("reset-default-btn").addEventListener("click", handleResetDatabase);
}

// ==========================================
// Chosung (Korean Consonant) Search Engine
// ==========================================
function getChosung(str) {
    const cho = ["ㄱ","ㄲ","ㄴ","ㄷ","ㄸ","ㄹ","ㅁ","ㅂ","ㅃ","ㅅ","ㅆ","ㅇ","ㅈ","ㅉ","ㅊ","ㅋ","ㅌ","ㅍ","ㅎ"];
    let result = "";
    for(let i=0; i<str.length; i++) {
        let code = str.charCodeAt(i) - 44032;
        if(code > -1 && code < 11172) {
            result += cho[Math.floor(code / 588)];
        } else {
            result += str.charAt(i);
        }
    }
    return result;
}

function selectIngredient(name) {
    const ingredient = state.ingredients.find(i => i.name === name);
    if (!ingredient) return;
    
    state.selectedId = name;
    
    // Get available storage options for this ingredient
    let availableLocations = [];
    if (ingredient.storage) {
        availableLocations = Object.keys(ingredient.storage);
    }
    
    if (availableLocations.length > 0) {
        state.selectedStorage = availableLocations[0];
    } else {
        state.selectedStorage = null;
    }
    
    renderStorageOptions(ingredient);
    updateStickerPreview();
    
    // Update selected visual class in grid
    document.querySelectorAll(".ingredient-card").forEach(card => {
        if (card.dataset.name === name) {
            card.classList.add("selected");
        } else {
            card.classList.remove("selected");
        }
    });
}

function adjustPrepTime(action) {
    const current = new Date(state.prepTime);
    switch (action) {
        case "now":
            state.prepTime = new Date();
            break;
        case "-30m":
            state.prepTime = new Date(current.getTime() - 30 * 60000);
            break;
        case "+30m":
            state.prepTime = new Date(current.getTime() + 30 * 60000);
            break;
        case "-1h":
            state.prepTime = new Date(current.getTime() - 60 * 60000);
            break;
        case "+1h":
            state.prepTime = new Date(current.getTime() + 60 * 60000);
            break;
        case "-1d":
            state.prepTime = new Date(current.getTime() - 24 * 60 * 60000);
            break;
        case "+1d":
            state.prepTime = new Date(current.getTime() + 24 * 60 * 60000);
            break;
    }
    updatePrepTimeInputDisplay();
    updateStickerPreview();
}

// ==========================================
// Rendering Engine - Front Page
// ==========================================
function renderCategoryFilterTabs() {
    const tabsContainer = document.getElementById("dynamic-category-tabs");
    if (!tabsContainer) return;
    
    tabsContainer.innerHTML = "";
    
    // All
    const allTab = document.createElement("button");
    allTab.className = `category-tab ${state.filters.category === "all" ? "active" : ""}`;
    allTab.dataset.category = "all";
    allTab.textContent = "전체";
    allTab.addEventListener("click", handleCategoryFilterClick);
    tabsContainer.appendChild(allTab);
    
    // Dynamic Categories
    state.categories.forEach(cat => {
        const tab = document.createElement("button");
        tab.className = `category-tab ${state.filters.category === cat.name ? "active" : ""}`;
        tab.dataset.category = cat.name;
        tab.textContent = `${cat.emoji ? cat.emoji + ' ' : ''}${cat.name}`;
        tab.addEventListener("click", handleCategoryFilterClick);
        tabsContainer.appendChild(tab);
    });
}

function handleCategoryFilterClick(e) {
    document.querySelectorAll(".category-tab").forEach(t => t.classList.remove("active"));
    e.currentTarget.classList.add("active");
    state.filters.category = e.currentTarget.dataset.category;
    renderIngredients();
}

function renderIngredients() {
    if (!ingredientsGrid) return;
    ingredientsGrid.innerHTML = "";
    
    const searchVal = state.filters.search.toLowerCase();
    const searchChosung = getChosung(searchVal);
    
    const filtered = state.ingredients.filter(item => {
        if (state.filters.category !== "all" && item.category !== state.filters.category) {
            return false;
        }
        
        if (searchVal) {
            const name = item.name.toLowerCase();
            const nameChosung = getChosung(name);
            const abbr = (item.abbr || "").toLowerCase();
            
            const matchesName = name.includes(searchVal);
            const matchesChosung = nameChosung.includes(searchChosung);
            const matchesAbbr = abbr.includes(searchVal);
            
            return matchesName || matchesChosung || matchesAbbr;
        }
        
        return true;
    });
    
    if (filtered.length === 0) {
        ingredientsGrid.innerHTML = `
            <div class="empty-state" style="display:flex; grid-column: 1/-1; justify-content:center; align-items:center; height:200px; color:var(--text-muted);">
                조건에 맞는 재료가 없습니다
            </div>
        `;
        return;
    }
    
    filtered.forEach(item => {
        const card = document.createElement("div");
        card.className = `ingredient-card ${state.selectedId === item.name ? 'selected' : ''}`;
        card.dataset.name = item.name;
        
        const categoryObj = state.categories.find(c => c.name === item.category);
        const categoryLabel = categoryObj ? `${categoryObj.emoji || ''} ${item.category}` : item.category;
        
        let storagePillsHTML = "";
        if (item.storage) {
            Object.entries(item.storage).forEach(([locName, data]) => {
                if (data && data.days !== null) {
                    storagePillsHTML += `<span class="card-limit-pill">${locName.slice(0,2)}:${data.days}일</span>`;
                }
            });
        }
        
        card.innerHTML = `
            <div class="card-category" style="background: rgba(99, 102, 241, 0.15); color: var(--primary-color); border: 1px solid rgba(99, 102, 241, 0.2);">${categoryLabel}</div>
            <div class="card-name">${item.name}</div>
            ${item.abbr ? `<div class="card-abbr-badge">${item.abbr}</div>` : ''}
            <div class="card-limits">
                ${storagePillsHTML}
            </div>
        `;
        
        card.addEventListener("click", () => {
            selectIngredient(item.name);
        });
        
        ingredientsGrid.appendChild(card);
    });
}

function renderStorageOptions(ingredient) {
    if (!selectedIngDisplay || !storageOptionsContainer) return;
    
    selectedIngDisplay.innerHTML = `
        <span>${ingredient.name}</span>
        ${ingredient.abbr ? `<span class="badge" style="background:var(--primary-color); padding:2px 8px; border-radius:4px; font-size:0.8rem;">${ingredient.abbr}</span>` : ''}
    `;
    
    storageOptionsContainer.innerHTML = "";
    
    state.locations.forEach(loc => {
        const config = ingredient.storage && ingredient.storage[loc.name];
        const hasValue = !!config;
        const days = hasValue ? config.days : null;
        
        const optCard = document.createElement("div");
        optCard.className = `storage-option-card ${!hasValue ? 'disabled' : ''} ${state.selectedStorage === loc.name ? 'selected' : ''}`;
        
        optCard.innerHTML = `
            <div class="storage-title">${loc.name}</div>
            <div class="storage-days">${hasValue ? `${days}일` : 'N/A'}</div>
        `;
        
        if (hasValue) {
            optCard.addEventListener("click", () => {
                state.selectedStorage = loc.name;
                renderStorageOptions(ingredient);
                updateStickerPreview();
            });
        }
        
        storageOptionsContainer.appendChild(optCard);
    });
}

// ==========================================
// Rendering Engine - Management Tab
// ==========================================
function renderCategoryChips() {
    const list = document.getElementById("manage-categories-list");
    if (!list) return;
    
    list.innerHTML = "";
    state.categories.forEach(cat => {
        const chip = document.createElement("div");
        chip.className = "tag-chip";
        chip.innerHTML = `
            <span>${cat.emoji ? cat.emoji + ' ' : ''}${cat.name}</span>
            <button type="button" class="delete-chip-btn">&times;</button>
        `;
        chip.querySelector(".delete-chip-btn").addEventListener("click", async (e) => {
            e.stopPropagation();
            if (confirm(`'${cat.name}' 카테고리를 삭제하시겠습니까?\n이 카테고리에 속한 재료들은 카테고리 정보가 그대로 남지만 목록 필터에서 이 카테고리는 없어집니다.`)) {
                try {
                    await apiDelete(`/api/categories/${cat.id}`);
                    state.categories = await apiGet("/api/categories");
                    renderCategoryChips();
                    renderCategoryDropdown();
                    renderCategoryFilterTabs();
                    renderIngredients();
                } catch (err) {
                    alert("카테고리 삭제 실패: " + err.message);
                }
            }
        });
        list.appendChild(chip);
    });
}

function renderLocationChips() {
    const list = document.getElementById("manage-locations-list");
    if (!list) return;
    
    list.innerHTML = "";
    state.locations.forEach(loc => {
        const chip = document.createElement("div");
        chip.className = "tag-chip";
        chip.innerHTML = `
            <span>${loc.name}</span>
            <button type="button" class="delete-chip-btn">&times;</button>
        `;
        chip.querySelector(".delete-chip-btn").addEventListener("click", async (e) => {
            e.stopPropagation();
            if (confirm(`'${loc.name}' 보관위치를 삭제하시겠습니까?\n이 보관위치로 설정된 모든 재료의 해당 위치 기한 값이 영구 삭제됩니다.`)) {
                try {
                    await apiDelete(`/api/storage-locations/${loc.id}`);
                    await loadAllData();
                    renderLocationChips();
                    renderStorageFieldsInForm();
                    renderRegisteredIngredientsTable();
                    renderIngredients();
                    
                    if (state.selectedStorage === loc.name) {
                        state.selectedStorage = null;
                    }
                    if (state.selectedId) {
                        const ing = state.ingredients.find(i => i.name === state.selectedId);
                        if (ing) renderStorageOptions(ing);
                    }
                } catch (err) {
                    alert("보관위치 삭제 실패: " + err.message);
                }
            }
        });
        list.appendChild(chip);
    });
}

function renderCategoryDropdown() {
    const select = document.getElementById("mgmt-new-category");
    if (!select) return;
    
    select.innerHTML = "";
    state.categories.forEach(cat => {
        const opt = document.createElement("option");
        opt.value = cat.name;
        opt.textContent = `${cat.emoji ? cat.emoji + ' ' : ''}${cat.name}`;
        select.appendChild(opt);
    });
}

function renderStorageFieldsInForm() {
    const container = document.getElementById("mgmt-storage-fields");
    if (!container) return;
    
    container.innerHTML = "";
    if (state.locations.length === 0) {
        container.innerHTML = `<div style="grid-column:1/-1; text-align:center; padding:10px; color:var(--text-muted); font-size:0.82rem;">등록된 보관위치가 없습니다.</div>`;
        return;
    }
    
    state.locations.forEach(loc => {
        const group = document.createElement("div");
        group.className = "storage-field-group";
        group.innerHTML = `
            <label>${loc.name}</label>
            <div class="storage-field-input-wrapper">
                <input type="number" class="mgmt-storage-input" data-loc-id="${loc.id}" min="0" placeholder="기한(일)">
                <span style="font-size:0.75rem; color:var(--text-muted);">일</span>
            </div>
        `;
        container.appendChild(group);
    });
}

function renderRegisteredIngredientsTable() {
    const headerRow = document.getElementById("mgmt-table-header");
    const tbody = document.getElementById("mgmt-table-body");
    if (!headerRow || !tbody) return;
    
    headerRow.innerHTML = `
        <th>카테고리</th>
        <th>재료명</th>
        <th>약어</th>
    `;
    state.locations.forEach(loc => {
        const th = document.createElement("th");
        th.textContent = loc.name;
        headerRow.appendChild(th);
    });
    const actTh = document.createElement("th");
    actTh.textContent = "동작";
    headerRow.appendChild(actTh);
    
    tbody.innerHTML = "";
    state.ingredients.forEach(ing => {
        const tr = document.createElement("tr");
        
        let storageCells = "";
        state.locations.forEach(loc => {
            const shelfDays = ing.storage && ing.storage[loc.name] ? ing.storage[loc.name].days : null;
            storageCells += `<td>${shelfDays !== null ? `${shelfDays}일` : '-'}</td>`;
        });
        
        tr.innerHTML = `
            <td><strong class="cat-tag" style="background: rgba(255,255,255,0.05); color: var(--text-primary); border: 1px solid var(--card-border);">${ing.category}</strong></td>
            <td>${ing.name}</td>
            <td>${ing.abbr || '-'}</td>
            ${storageCells}
            <td>
                <button class="db-action-btn delete" data-name="${ing.name}" title="삭제">
                    <i data-lucide="trash-2" style="width:14px;height:14px;"></i>
                </button>
            </td>
        `;
        
        tr.querySelector(".db-action-btn.delete").addEventListener("click", () => {
            deleteIngredient(ing.name);
        });
        
        tbody.appendChild(tr);
    });
    
    lucide.createIcons();
}

// ==========================================
// Handlers for Management Forms
// ==========================================
async function handleAddCategory(e) {
    e.preventDefault();
    const nameInput = document.getElementById("new-cat-name");
    const emojiInput = document.getElementById("new-cat-emoji");
    const name = nameInput.value.trim();
    const emoji = emojiInput.value.trim();
    
    if (state.categories.some(c => c.name === name)) {
        alert("이미 존재하는 카테고리입니다.");
        return;
    }
    
    try {
        await apiPost("/api/categories", { name, emoji });
        state.categories = await apiGet("/api/categories");
        renderCategoryChips();
        renderCategoryDropdown();
        renderCategoryFilterTabs();
        
        nameInput.value = "";
        emojiInput.value = "";
    } catch (err) {
        alert("카테고리 추가 실패: " + err.message);
    }
}

async function handleAddLocation(e) {
    e.preventDefault();
    const nameInput = document.getElementById("new-loc-name");
    const name = nameInput.value.trim();
    
    if (state.locations.some(l => l.name === name)) {
        alert("이미 존재하는 보관위치입니다.");
        return;
    }
    
    try {
        await apiPost("/api/storage-locations", { name });
        state.locations = await apiGet("/api/storage-locations");
        renderLocationChips();
        renderStorageFieldsInForm();
        renderRegisteredIngredientsTable();
        
        nameInput.value = "";
    } catch (err) {
        alert("보관위치 추가 실패: " + err.message);
    }
}

async function handleMgmtAddIngredient(e) {
    e.preventDefault();
    const nameInput = document.getElementById("mgmt-new-name");
    const abbrInput = document.getElementById("mgmt-new-abbr");
    const categorySelect = document.getElementById("mgmt-new-category");
    
    const name = nameInput.value.trim();
    const abbr = abbrInput.value.trim().toUpperCase();
    const category = categorySelect.value;
    
    if (!name || !category) {
        alert("재료명과 카테고리는 필수입니다.");
        return;
    }
    
    if (state.ingredients.some(i => i.name.toLowerCase() === name.toLowerCase())) {
        alert("이미 존재하는 재료입니다.");
        return;
    }
    
    const storage = {};
    const storageInputs = document.querySelectorAll(".mgmt-storage-input");
    storageInputs.forEach(inp => {
        const locId = inp.dataset.locId;
        const val = inp.value.trim();
        if (val !== "") {
            storage[locId] = parseInt(val);
        }
    });
    
    try {
        await apiPost("/api/ingredients", { name, category, abbr, storage });
        await loadAllData();
        renderRegisteredIngredientsTable();
        renderIngredients();
        
        document.getElementById("mgmt-add-ingredient-form").reset();
    } catch (err) {
        alert("재료 등록 실패: " + err.message);
    }
}

async function deleteIngredient(name) {
    if (confirm(`'${name}' 재료를 삭제하시겠습니까?`)) {
        try {
            await apiDelete(`/api/ingredients/${encodeURIComponent(name)}`);
            await loadAllData();
            renderRegisteredIngredientsTable();
            renderIngredients();
            
            if (state.selectedId === name) {
                if (state.ingredients.length > 0) {
                    selectIngredient(state.ingredients[0].name);
                } else {
                    state.selectedId = null;
                    state.selectedStorage = null;
                    selectedIngDisplay.textContent = "재료를 선택해 주세요";
                    storageOptionsContainer.innerHTML = "";
                }
            }
        } catch (err) {
            alert("재료 삭제 실패: " + err.message);
        }
    }
}

async function handleResetDatabase() {
    if (confirm("정말로 모든 설정을 기본값으로 리셋하시겠습니까?\n직접 추가하거나 수정한 카테고리, 보관위치, 재료, 라벨 규격이 전부 삭제됩니다.")) {
        try {
            await apiPost("/api/ingredients/reset", {});
            await loadAllData();
            
            renderCategoryFilterTabs();
            renderIngredients();
            renderCategoryChips();
            renderLocationChips();
            renderCategoryDropdown();
            renderStorageFieldsInForm();
            renderRegisteredIngredientsTable();
            renderPresetButtons();
            
            if (state.ingredients.length > 0) {
                selectIngredient(state.ingredients[0].name);
            } else {
                state.selectedId = null;
                state.selectedStorage = null;
                selectedIngDisplay.textContent = "재료를 선택해 주세요";
                storageOptionsContainer.innerHTML = "";
            }
            
            alert("전체 리셋이 완료되었습니다.");
        } catch (err) {
            alert("전체 리셋 실패: " + err.message);
        }
    }
}

// ==========================================
// Preview & Expiration Calculations
// ==========================================
function formatDate(date) {
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    const yyyy = date.getFullYear();
    const mm = String(date.getMonth() + 1).padStart(2, '0');
    const dd = String(date.getDate()).padStart(2, '0');
    const day = days[date.getDay()];
    const hh = String(date.getHours()).padStart(2, '0');
    const min = String(date.getMinutes()).padStart(2, '0');
    
    return `${yyyy}-${mm}-${dd} (${day}) ${hh}:${min}`;
}

function updateStickerPreview() {
    const ingredient = state.ingredients.find(i => i.name === state.selectedId);
    if (!ingredient) return;
    
    if (ingredient.abbr) {
        stickerAbbr.textContent = ingredient.abbr;
        stickerAbbr.style.display = "flex";
    } else {
        stickerAbbr.style.display = "none";
    }
    
    stickerName.textContent = ingredient.name;
    
    stickerLoc.textContent = state.selectedStorage ? `${state.selectedStorage} 보관` : "보관위치 미지정";
    stickerPrepDate.textContent = formatDate(state.prepTime);
    
    let shelfLifeDays = 0;
    if (state.selectedStorage && ingredient.storage && ingredient.storage[state.selectedStorage]) {
        shelfLifeDays = ingredient.storage[state.selectedStorage].days || 0;
    }
    
    const expireTime = new Date(state.prepTime.getTime() + shelfLifeDays * 24 * 60 * 60000);
    stickerExpireDate.textContent = formatDate(expireTime);
    stickerStaffVal.textContent = state.staffName ? state.staffName : "-";
}

// ==========================================
// Print Operation
// ==========================================
function triggerPrint() {
    const quantity = state.printQty;
    printStickerContainer.innerHTML = "";
    
    const w = parseFloat(document.getElementById("label-width").value) || 50;
    const h = parseFloat(document.getElementById("label-height").value) || 30;
    
    let printStyle = document.getElementById("dynamic-print-style");
    if (!printStyle) {
        printStyle = document.createElement("style");
        printStyle.id = "dynamic-print-style";
        document.head.appendChild(printStyle);
    }
    printStyle.innerHTML = `
        @page {
            size: ${w}mm ${h}mm;
            margin: 0;
        }
        .print-only-container .sticker-preview-content {
            width: ${w}mm !important;
            height: ${h}mm !important;
            padding: ${h * 0.12}mm ${w * 0.08}mm !important;
        }
    `;
    
    const previewContent = document.getElementById("sticker-preview").cloneNode(true);
    previewContent.removeAttribute("id");
    
    for (let i = 0; i < quantity; i++) {
        const item = previewContent.cloneNode(true);
        printStickerContainer.appendChild(item);
    }
    
    window.print();
}

// ==========================================
// Settings Modal
// ==========================================
function openSettingsModal() {
    settingsModal.style.display = "flex";
    document.body.classList.add("modal-open");
    renderPresetButtons();
}

function closeSettingsModal() {
    settingsModal.style.display = "none";
    document.body.classList.remove("modal-open");
}

// ==========================================
// Theme Logic
// ==========================================
function initTheme() {
    const savedTheme = localStorage.getItem("label_theme");
    if (savedTheme) {
        state.theme = savedTheme;
    } else {
        const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
        state.theme = prefersDark ? "dark" : "light";
    }
    
    if (state.theme === "light") {
        document.body.classList.add("light-theme");
    } else {
        document.body.classList.remove("light-theme");
    }
}

function toggleTheme() {
    if (state.theme === "dark") {
        state.theme = "light";
        document.body.classList.add("light-theme");
    } else {
        state.theme = "dark";
        document.body.classList.remove("light-theme");
    }
    localStorage.setItem("label_theme", state.theme);
}
