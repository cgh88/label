// ==========================================
// Server DB API Wrapper & Helper
// ==========================================
async function apiGet(url) {
    const response = await fetch(url);
    if (!response.ok) {
        const err = await response.json().catch(() => ({}));
        const e = new Error(err.error || "데이터 조회 실패");
        e.status = response.status;
        e.ipBlocked = err.ipBlocked;
        e.clientIp = err.clientIp;
        throw e;
    }
    return await response.json();
}

async function apiPost(url, data) {
    const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data)
    });
    if (!response.ok) {
        const err = await response.json().catch(() => ({}));
        const e = new Error(err.error || "요청 처리 실패");
        e.status = response.status;
        e.ipBlocked = err.ipBlocked;
        e.clientIp = err.clientIp;
        throw e;
    }
    return await response.json();
}

async function apiPut(url, data) {
    const response = await fetch(url, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data)
    });
    if (!response.ok) {
        const err = await response.json().catch(() => ({}));
        const e = new Error(err.error || "수정 실패");
        e.status = response.status;
        e.ipBlocked = err.ipBlocked;
        e.clientIp = err.clientIp;
        throw e;
    }
    return await response.json();
}

async function apiDelete(url) {
    const response = await fetch(url, { method: "DELETE" });
    if (!response.ok) {
        const err = await response.json().catch(() => ({}));
        const e = new Error(err.error || "삭제 실패");
        e.status = response.status;
        e.ipBlocked = err.ipBlocked;
        e.clientIp = err.clientIp;
        throw e;
    }
    return await response.json();
}

async function loadAppInfo() {
    try {
        const data = await apiGet('/api/app-info');
        const metaEl = document.getElementById('apk-meta-info');
        const badgeEl = document.getElementById('apk-download-badge');
        if (metaEl && data.exists) {
            const bDate = new Date(data.buildDate);
            const yyyy = bDate.getFullYear();
            const mm = String(bDate.getMonth() + 1).padStart(2, '0');
            const dd = String(bDate.getDate()).padStart(2, '0');
            const hh = String(bDate.getHours()).padStart(2, '0');
            const min = String(bDate.getMinutes()).padStart(2, '0');
            const dateStr = `${yyyy}-${mm}-${dd} ${hh}:${min}`;
            metaEl.innerText = `v${data.version} (#${data.buildNumber}) · ${dateStr} (${data.fileSizeMb})`;
        }
        if (badgeEl && data.exists) {
            badgeEl.title = `최신 안드로이드 태블릿 APK 다운로드\n버전: v${data.version} (빌드 #${data.buildNumber})\n빌드일시: ${data.buildDate}\n용량: ${data.fileSizeMb}`;
        }
    } catch (e) {
        console.warn('App info fetch error:', e);
    }
}
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', loadAppInfo);
} else {
    loadAppInfo();
}

function clearElement(element) {
    element.replaceChildren();
}

function createTextElement(tagName, className, text) {
    const element = document.createElement(tagName);
    if (className) element.className = className;
    element.textContent = text;
    return element;
}

function appendDeleteButton(container, onClick) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "delete-chip-btn";
    button.textContent = "\u00d7";
    button.addEventListener("click", onClick);
    container.appendChild(button);
    return button;
}

function renderMainDataViews() {
    renderCategoryFilterTabs();
    renderIngredients();
    renderCategoryChips();
    renderLocationChips();
    renderCategoryDropdown();
    renderStorageFieldsInForm();
    renderRegisteredIngredientsTable();
}

async function reloadAndRenderMainViews() {
    await loadAllData();
    renderMainDataViews();
}

// ==========================================
// App State
// ==========================================
let state = {
    ingredients: [],
    categories: [],
    locations: [],
    user: null,            // Currently logged in user { username, role }
    selectedId: null,      // Name string of selected ingredient
    selectedStorage: null, // Name of selected storage location (e.g. "워크인 랙산")
    prepTime: null,        // Date Object
    staffName: "",
    printQty: 1,
    theme: "dark",
    activeTab: "tab-print",
    filters: {
        category: "all",
        search: "",
        mgmtSearch: ""
    },
    layout: {
        topPadding: 10,
        leftPadding: 30,
        rightPadding: 13,
        bottomPadding: 0,
        verticalGap: 4,
        showLine1: true,
        sizeLine1: 1.0,
        showLine2: true,
        sizeLine2: 1.0,
        showLine3: true,
        sizeLine3: 1.0,
        showLine4: false,
        sizeLine4: 0.5
    }
};

// ==========================================
// DOM Cache (Static elements)
// ==========================================
const ingredientsGrid = document.getElementById("ingredients-grid");
const searchInput = document.getElementById("ingredient-search");
const mgmtSearchInput = document.getElementById("mgmt-ingredient-search");

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

const stickerLine1 = document.getElementById("sticker-line-1");
const stickerLine2 = document.getElementById("sticker-line-2");
const stickerLine3 = document.getElementById("sticker-line-3");
const stickerLine4 = document.getElementById("sticker-line-4");

// Control buttons
const printLabelBtn = document.getElementById("print-label-btn");
const themeToggleBtn = document.getElementById("theme-toggle-btn");
const printStickerContainer = document.getElementById("print-sticker-container");

// Modals
const settingsOpenBtn = document.getElementById("settings-open-btn");
const settingsCloseBtn = document.getElementById("settings-close-btn");
const settingsModal = document.getElementById("settings-modal");

// Edit Ingredient Modal
const editIngredientModal = document.getElementById("edit-ingredient-modal");
const editModalCloseBtn = document.getElementById("edit-modal-close-btn");
const editModalCancelBtn = document.getElementById("edit-modal-cancel-btn");
const editIngredientForm = document.getElementById("mgmt-edit-ingredient-form");
const editOldNameInput = document.getElementById("mgmt-edit-old-name");
const editNameInput = document.getElementById("mgmt-edit-name");
const editAbbrInput = document.getElementById("mgmt-edit-abbr");
const editCategorySelect = document.getElementById("mgmt-edit-category");
const editStorageFieldsContainer = document.getElementById("mgmt-edit-storage-fields");

// Login Elements
const loginOverlay = document.getElementById("login-overlay");
const loginForm = document.getElementById("login-form");
const loginUsernameInput = document.getElementById("login-username");
const loginPasswordInput = document.getElementById("login-password");
const loginErrorMsg = document.getElementById("login-error-msg");
const logoutBtn = document.getElementById("logout-btn");

// ==========================================
// Initialization & Event Binding
// ==========================================
document.addEventListener("DOMContentLoaded", async () => {
    initTheme();
    initDateTime();
    loadStaffName();
    
    initTabs();
    initSauceSystem();
    initLabelSizeControls();
    initLayoutSettings();
    initEmojiPicker();
    setupEventHandlers();
    
    await checkAuthStatus();
    
    lucide.createIcons();
});

// ==========================================
// Core States & CRUD Operations
// ==========================================
async function loadAllData() {
    state.ingredients = await apiGet("/api/ingredients");
    state.categories = await apiGet("/api/categories");
    state.locations = await apiGet("/api/storage-locations");
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

// Fixed label size: 55mm × 20mm
const FIXED_LABEL_W = 55;
const FIXED_LABEL_H = 20;

function initLabelSizeControls() {
    // Label size is fixed at 55×20mm - clear any stale saved values
    localStorage.setItem("label_width", FIXED_LABEL_W);
    localStorage.setItem("label_height", FIXED_LABEL_H);
    updateLabelSize();
}


function updateLabelSize() {
    // Size is fixed at 55×20mm
    const w = FIXED_LABEL_W;
    const h = FIXED_LABEL_H;

    document.documentElement.style.setProperty("--label-w", w);
    document.documentElement.style.setProperty("--label-h", h);

    const previewSizeLabel = document.getElementById("preview-size-label");
    if (previewSizeLabel) {
        previewSizeLabel.textContent = `${w} × ${h}`;
    }
}

// Global layout settings save handler (must be global for inline HTML oninput handlers)
window.saveLayoutState = function() {
    saveLayoutSettings();
};

function loadLayoutSettings() {
    const saved = localStorage.getItem("label_layout_settings");
    if (saved) {
        try {
            state.layout = { ...state.layout, ...JSON.parse(saved) };
        } catch (e) {
            console.error("Failed to parse layout settings:", e);
        }
    }
    
    // Apply values to inputs in the settings modal
    const setVal = (id, val) => {
        const el = document.getElementById(id);
        if (el) el.value = val;
    };
    const setChecked = (id, val) => {
        const el = document.getElementById(id);
        if (el) el.checked = val;
    };
    
    setVal("layout-top-padding", state.layout.topPadding);
    setVal("layout-left-padding", state.layout.leftPadding);
    setVal("layout-right-padding", state.layout.rightPadding);
    setVal("layout-bottom-padding", state.layout.bottomPadding);
    setVal("layout-vertical-gap", state.layout.verticalGap);
    
    setChecked("layout-show-line-1", state.layout.showLine1);
    setVal("layout-size-line-1", state.layout.sizeLine1);
    setChecked("layout-show-line-2", state.layout.showLine2);
    setVal("layout-size-line-2", state.layout.sizeLine2);
    setChecked("layout-show-line-3", state.layout.showLine3);
    setVal("layout-size-line-3", state.layout.sizeLine3);
    setChecked("layout-show-line-4", state.layout.showLine4);
    setVal("layout-size-line-4", state.layout.sizeLine4);
}

function saveLayoutSettings() {
    const getVal = (id) => parseFloat(document.getElementById(id).value) || 0;
    const getChecked = (id) => document.getElementById(id).checked;
    
    state.layout = {
        topPadding: getVal("layout-top-padding"),
        leftPadding: getVal("layout-left-padding"),
        rightPadding: getVal("layout-right-padding"),
        bottomPadding: getVal("layout-bottom-padding"),
        verticalGap: getVal("layout-vertical-gap"),
        showLine1: getChecked("layout-show-line-1"),
        sizeLine1: getVal("layout-size-line-1"),
        showLine2: getChecked("layout-show-line-2"),
        sizeLine2: getVal("layout-size-line-2"),
        showLine3: getChecked("layout-show-line-3"),
        sizeLine3: getVal("layout-size-line-3"),
        showLine4: getChecked("layout-show-line-4"),
        sizeLine4: getVal("layout-size-line-4")
    };
    localStorage.setItem("label_layout_settings", JSON.stringify(state.layout));
    applyLayoutSettings();
}

function applyLayoutSettings() {
    const preview = document.getElementById("sticker-preview");
    if (!preview) return;
    
    const lay = state.layout;
    preview.style.padding = `${lay.topPadding}px ${lay.rightPadding}px ${lay.bottomPadding}px ${lay.leftPadding}px`;
    preview.style.gap = `${lay.verticalGap}px`;
    
    const lines = [
        { show: lay.showLine1, size: lay.sizeLine1, el: document.getElementById("sticker-line-1") },
        { show: lay.showLine2, size: lay.sizeLine2, el: document.getElementById("sticker-line-2") },
        { show: lay.showLine3, size: lay.sizeLine3, el: document.getElementById("sticker-line-3") },
        { show: lay.showLine4, size: lay.sizeLine4, el: document.getElementById("sticker-line-4") }
    ];
    
    lines.forEach((line) => {
        if (line.el) {
            if (line.show) {
                line.el.style.display = "block";
                // Use px (1 size unit = 16px = 2.5mm at the 6.4px/mm preview scale)
                // so the preview is independent of the root font-size and matches
                // the mm-based sizes used by triggerPrint().
                line.el.style.fontSize = `${(line.size * 16).toFixed(2)}px`;
                // Match the line-height forced in the print stylesheet.
                line.el.style.lineHeight = "1.15";
            } else {
                line.el.style.display = "none";
            }
        }
    });
}

function initLayoutSettings() {
    loadLayoutSettings();
    applyLayoutSettings();
    
    // Bind change/input events to all layout elements
    const inputs = [
        "layout-top-padding", "layout-left-padding", "layout-right-padding", "layout-bottom-padding",
        "layout-vertical-gap", "layout-size-line-1", "layout-size-line-2", "layout-size-line-3", "layout-size-line-4"
    ];
    inputs.forEach(id => {
        const el = document.getElementById(id);
        if (el) el.addEventListener("input", saveLayoutSettings);
    });
    
    const checkboxes = [
        "layout-show-line-1", "layout-show-line-2", "layout-show-line-3", "layout-show-line-4"
    ];
    checkboxes.forEach(id => {
        const el = document.getElementById(id);
        if (el) el.addEventListener("change", saveLayoutSettings);
    });
}


function initDateTime() {
    state.prepTime = new Date();
    updatePrepTimeInputDisplay();
}

function updatePrepTimeInputDisplay() {
    if (!prepTimeInput) return;
    const tzOffset = state.prepTime.getTimezoneOffset() * 60000;
    const localISOTime = (new Date(state.prepTime - tzOffset)).toISOString().slice(0, 16);
    prepTimeInput.value = localISOTime;
}

function loadStaffName() {
    const savedStaff = localStorage.getItem("label_staff_name");
    if (savedStaff) {
        state.staffName = savedStaff;
        if (staffInput) staffInput.value = savedStaff;
        if (stickerStaffVal) {
            stickerStaffVal.textContent = savedStaff;
        }
    }
}

function setupEventHandlers() {
    // Search
    if (searchInput) {
        searchInput.addEventListener("input", (e) => {
            state.filters.search = e.target.value.trim();
            renderIngredients();
        });
    }

    if (mgmtSearchInput) {
        mgmtSearchInput.addEventListener("input", (e) => {
            state.filters.mgmtSearch = e.target.value.trim();
            renderRegisteredIngredientsTable();
        });
    }
    
    // Theme Toggle
    if (themeToggleBtn) themeToggleBtn.addEventListener("click", toggleTheme);
    
    // Prep Time Input Manual Change
    if (prepTimeInput) {
        prepTimeInput.addEventListener("change", (e) => {
            if (e.target.value) {
                state.prepTime = new Date(e.target.value);
                updateStickerPreview();
            }
        });
    }
    
    // Time adjustment buttons
    document.querySelectorAll(".time-adjust-btn").forEach(btn => {
        btn.addEventListener("click", (e) => {
            const action = e.target.closest("button").dataset.action;
            adjustPrepTime(action);
        });
    });
    
    // Staff Input
    if (staffInput) {
        staffInput.addEventListener("input", (e) => {
            state.staffName = e.target.value;
            localStorage.setItem("label_staff_name", state.staffName);
            updateStickerPreview();
        });
    }
    
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

    // Edit modal controls
    if (editModalCloseBtn) {
        editModalCloseBtn.addEventListener("click", closeEditModal);
    }
    if (editModalCancelBtn) {
        editModalCancelBtn.addEventListener("click", closeEditModal);
    }
    if (editIngredientModal) {
        editIngredientModal.addEventListener("click", (e) => {
            if (e.target === editIngredientModal) closeEditModal();
        });
    }
    if (editIngredientForm) {
        editIngredientForm.addEventListener("submit", handleMgmtEditIngredient);
    }

    // Forms in Management Tab
    document.getElementById("add-category-form").addEventListener("submit", handleAddCategory);
    document.getElementById("add-location-form").addEventListener("submit", handleAddLocation);
    document.getElementById("mgmt-add-ingredient-form").addEventListener("submit", handleMgmtAddIngredient);
    document.getElementById("reset-default-btn").addEventListener("click", handleResetDatabase);

    // Login & Logout
    if (loginForm) {
        loginForm.addEventListener("submit", handleLogin);
    }
    if (logoutBtn) {
        logoutBtn.addEventListener("click", handleLogout);
    }

    // Access Denied Modal Close
    const accessDeniedCloseBtn = document.getElementById("access-denied-close-btn");
    if (accessDeniedCloseBtn) {
        accessDeniedCloseBtn.addEventListener("click", closeAccessDeniedModal);
    }

    // Admin IP Allowlist Controls
    const fillIpBtn = document.getElementById("fill-current-ip-btn");
    const saveAdminIpBtn = document.getElementById("save-admin-ip-btn");

    if (fillIpBtn) {
        fillIpBtn.addEventListener("click", () => {
            const displayEl = document.getElementById("current-client-ip-display");
            const inputEl = document.getElementById("admin-allowed-ips-input");
            if (displayEl && inputEl && displayEl.dataset.clientIp) {
                const currentIp = displayEl.dataset.clientIp;
                let existing = inputEl.value.trim();
                if (!existing) {
                    inputEl.value = currentIp;
                } else if (!existing.includes(currentIp)) {
                    inputEl.value = `${existing}, ${currentIp}`;
                }
            }
        });
    }

    if (saveAdminIpBtn) {
        saveAdminIpBtn.addEventListener("click", async () => {
            const inputEl = document.getElementById("admin-allowed-ips-input");
            if (!inputEl) return;
            const val = inputEl.value.trim();
            try {
                saveAdminIpBtn.disabled = true;
                saveAdminIpBtn.textContent = "저장 중...";
                await apiPost('/api/system-settings', { setting_key: 'admin_allowed_ips', setting_value: val });
                alert("관리자 접속 IP 설정이 성공적으로 저장되었습니다.");
            } catch (err) {
                if (err.ipBlocked || (err.message && err.message.includes('허용되지 않은 IP'))) {
                    showAccessDeniedModal(err.message, err.clientIp);
                } else {
                    alert("저장 실패: " + err.message);
                }
            } finally {
                saveAdminIpBtn.disabled = false;
                saveAdminIpBtn.textContent = "저장";
            }
        });
    }

    // Excel Upload
    const uploadExcelBtn = document.getElementById("upload-excel-btn");
    const excelFileInput = document.getElementById("excel-file-input");
    if (uploadExcelBtn && excelFileInput) {
        uploadExcelBtn.addEventListener("click", () => {
            excelFileInput.click();
        });
        excelFileInput.addEventListener("change", async (e) => {
            const file = e.target.files[0];
            if (!file) return;

            const formData = new FormData();
            formData.append("file", file);

            try {
                uploadExcelBtn.disabled = true;
                const span = uploadExcelBtn.querySelector("span");
                if (span) span.textContent = "업로드 중...";

                const response = await fetch("/api/ingredients/upload-excel", {
                    method: "POST",
                    body: formData
                });

                if (!response.ok) {
                    const err = await response.json();
                    throw new Error(err.error || "엑셀 업로드 실패");
                }

                const result = await response.json();
                alert(`엑셀 파일 업로드 성공! ${result.count}개의 재료 데이터가 업데이트되었습니다.`);
                
                await reloadAndRenderMainViews();
                if (state.ingredients.length > 0) {
                    selectIngredient(state.ingredients[0].name);
                }
            } catch (err) {
                alert("엑셀 파일 업로드 중 오류가 발생했습니다: " + err.message);
            } finally {
                uploadExcelBtn.disabled = false;
                const span = uploadExcelBtn.querySelector("span");
                if (span) span.textContent = "엑셀 업로드";
                excelFileInput.value = "";
            }
        });
    }

    // Login & Logout
    if (loginForm) {
        loginForm.addEventListener("submit", handleLogin);
    }
    if (logoutBtn) {
        logoutBtn.addEventListener("click", handleLogout);
    }

    // Category tabs scroll buttons setup
    const tabsContainer = document.getElementById("dynamic-category-tabs");
    if (tabsContainer) {
        tabsContainer.addEventListener("scroll", updateCategoryTabsScrollButtons);
        window.addEventListener("resize", updateCategoryTabsScrollButtons);
    }
    
    const leftBtn = document.getElementById("tabs-scroll-left");
    if (leftBtn) {
        leftBtn.addEventListener("click", () => {
            if (tabsContainer) {
                tabsContainer.scrollBy({ left: -180, behavior: 'smooth' });
            }
        });
    }
    
    const rightBtn = document.getElementById("tabs-scroll-right");
    if (rightBtn) {
        rightBtn.addEventListener("click", () => {
            if (tabsContainer) {
                tabsContainer.scrollBy({ left: 180, behavior: 'smooth' });
            }
        });
    }
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
        state.selectedStorage = "입고";
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
    
    clearElement(tabsContainer);
    
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

    // Schedule scroll buttons update after DOM renders
    setTimeout(updateCategoryTabsScrollButtons, 50);
}

function updateCategoryTabsScrollButtons() {
    const tabsContainer = document.getElementById("dynamic-category-tabs");
    const leftBtn = document.getElementById("tabs-scroll-left");
    const rightBtn = document.getElementById("tabs-scroll-right");
    if (!tabsContainer || !leftBtn || !rightBtn) return;

    const scrollLeft = tabsContainer.scrollLeft;
    const scrollWidth = tabsContainer.scrollWidth;
    const clientWidth = tabsContainer.clientWidth;

    // Show left scroll button if scrolled to the right
    if (scrollLeft > 5) {
        leftBtn.classList.add("visible");
    } else {
        leftBtn.classList.remove("visible");
    }

    // Show right scroll button if there is overflow remaining to the right
    if (scrollLeft + clientWidth < scrollWidth - 5) {
        rightBtn.classList.add("visible");
    } else {
        rightBtn.classList.remove("visible");
    }
}

function handleCategoryFilterClick(e) {
    document.querySelectorAll(".category-tab").forEach(t => t.classList.remove("active"));
    e.currentTarget.classList.add("active");
    state.filters.category = e.currentTarget.dataset.category;
    renderIngredients();
}

function renderIngredients() {
    if (!ingredientsGrid) return;
    clearElement(ingredientsGrid);
    
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
        const emptyState = createTextElement("div", "empty-state", "조건에 맞는 재료가 없습니다");
        emptyState.style.cssText = "display:flex; grid-column: 1/-1; justify-content:center; align-items:center; height:200px; color:var(--text-muted);";
        ingredientsGrid.appendChild(emptyState);
        return;
    }
    
    filtered.forEach(item => {
        const card = document.createElement("div");
        card.className = `ingredient-card ${state.selectedId === item.name ? 'selected' : ''}`;
        card.dataset.name = item.name;
        
        const categoryObj = state.categories.find(c => c.name === item.category);
        const categoryLabel = categoryObj ? `${categoryObj.emoji || ''} ${item.category}` : item.category;
        
        const storagePills = [];
        if (item.storage) {
            Object.entries(item.storage).forEach(([locName, data]) => {
                if (data && data.days !== null) {
                    const loc = state.locations.find(l => l.name === locName);
                    const isHourUnit = loc ? loc.unit === "hour" : (locName === "소스보틀" || locName === "분할");
                    if (isHourUnit) {
                        if (locName === "분할" && data.days === 22) {
                            storagePills.push(`${locName.slice(0, 2)}:당일 22시`);
                        } else {
                            storagePills.push(`${locName.slice(0, 2)}:${data.days}시간`);
                        }
                    } else {
                        storagePills.push(`${locName.slice(0, 2)}:${data.days}일`);
                    }
                }
            });
        }

        const category = createTextElement("div", "card-category", categoryLabel);
        category.style.cssText = "background: rgba(99, 102, 241, 0.15); color: var(--primary-color); border: 1px solid rgba(99, 102, 241, 0.2);";
        card.appendChild(category);
        card.appendChild(createTextElement("div", "card-name", item.name));

        if (item.abbr) {
            card.appendChild(createTextElement("div", "card-abbr-badge", item.abbr));
        }

        const limits = document.createElement("div");
        limits.className = "card-limits";
        storagePills.forEach(label => {
            limits.appendChild(createTextElement("span", "card-limit-pill", label));
        });
        card.appendChild(limits);
        
        card.addEventListener("click", () => {
            selectIngredient(item.name);
        });
        
        ingredientsGrid.appendChild(card);
    });
}

function renderStorageOptions(ingredient) {
    if (!selectedIngDisplay || !storageOptionsContainer) return;

    clearElement(selectedIngDisplay);
    selectedIngDisplay.appendChild(createTextElement("span", "", ingredient.name));
    if (ingredient.abbr) {
        const badge = createTextElement("span", "badge", ingredient.abbr);
        badge.style.cssText = "background:var(--primary-color); padding:2px 8px; border-radius:4px; font-size:0.8rem;";
        selectedIngDisplay.appendChild(badge);
    }

    clearElement(storageOptionsContainer);
    
    state.locations.forEach(loc => {
        const config = ingredient.storage && ingredient.storage[loc.name];
        const hasValue = !!config;
        const days = hasValue ? config.days : null;
        
        const optCard = document.createElement("div");
        optCard.className = `storage-option-card ${!hasValue ? 'disabled' : ''} ${state.selectedStorage === loc.name ? 'selected' : ''}`;
        
        let daysText = "N/A";
        if (hasValue) {
            if (loc.unit === "hour") {
                if (loc.name === "분할" && days === 22) {
                    daysText = "당일 22시";
                } else {
                    daysText = `${days}시간`;
                }
            } else {
                daysText = `${days}일`;
            }
        }
        
        optCard.appendChild(createTextElement("div", "storage-title", loc.name));
        optCard.appendChild(createTextElement("div", "storage-days", daysText));
        
        if (hasValue) {
            optCard.addEventListener("click", () => {
                state.selectedStorage = loc.name;
                renderStorageOptions(ingredient);
                updateStickerPreview();
            });
        }
        
        storageOptionsContainer.appendChild(optCard);
    });

    // Virtual "입고" card
    const ipgoCard = document.createElement("div");
    ipgoCard.className = `storage-option-card ${state.selectedStorage === "입고" ? 'selected' : ''}`;
    ipgoCard.appendChild(createTextElement("div", "storage-title", "입고"));
    ipgoCard.appendChild(createTextElement("div", "storage-days", "상시"));
    ipgoCard.addEventListener("click", () => {
        state.selectedStorage = "입고";
        renderStorageOptions(ingredient);
        updateStickerPreview();
    });
    storageOptionsContainer.appendChild(ipgoCard);
}

// ==========================================
// Rendering Engine - Management Tab
// ==========================================
function renderCategoryChips() {
    const list = document.getElementById("manage-categories-list");
    if (!list) return;
    
    clearElement(list);
    state.categories.forEach(cat => {
        const chip = document.createElement("div");
        chip.className = "tag-chip";
        chip.appendChild(createTextElement("span", "", `${cat.emoji ? cat.emoji + ' ' : ''}${cat.name}`));
        appendDeleteButton(chip, async (e) => {
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
    
    clearElement(list);
    state.locations.forEach(loc => {
        const chip = document.createElement("div");
        chip.className = "tag-chip";
        const unitText = loc.unit === "hour" ? "시간" : "일";
        chip.appendChild(createTextElement("span", "", `${loc.name} (${unitText})`));
        appendDeleteButton(chip, async (e) => {
            e.stopPropagation();
            if (confirm(`${loc.name} 삭제하시겠습니까?`)) {
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
                    if (err.status === 401) {
                        alert("세션이 만료되었습니다. 다시 로그인해 주세요.");
                        loginOverlay.style.display = "flex";
                    } else if (err.status === 403) {
                        alert("관리자 권한이 필요합니다.");
                    } else {
                        alert("보관위치 삭제 실패: " + err.message);
                    }
                }
            }
        });
        list.appendChild(chip);
    });
}

function renderCategoryDropdown() {
    const select = document.getElementById("mgmt-new-category");
    if (!select) return;
    
    clearElement(select);
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
    
    clearElement(container);
    if (state.locations.length === 0) {
        const emptyState = createTextElement("div", "", "등록된 보관위치가 없습니다.");
        emptyState.style.cssText = "grid-column:1/-1; text-align:center; padding:10px; color:var(--text-muted); font-size:0.82rem;";
        container.appendChild(emptyState);
        return;
    }
    
    state.locations.forEach(loc => {
        const group = document.createElement("div");
        group.className = "storage-field-group";
        group.appendChild(createTextElement("label", "", loc.name));

        const wrapper = document.createElement("div");
        wrapper.className = "storage-field-input-wrapper";
        const input = document.createElement("input");
        input.type = "number";
        input.className = "mgmt-storage-input";
        input.dataset.locId = loc.id;
        input.min = "1";
        const isHourUnit = loc.unit === "hour";
        input.placeholder = isHourUnit ? "기한(시간)" : "기한(일)";
        wrapper.appendChild(input);

        const unit = createTextElement("span", "", isHourUnit ? "시간" : "일");
        unit.style.cssText = "font-size:0.75rem; color:var(--text-muted);";
        wrapper.appendChild(unit);
        group.appendChild(wrapper);
        container.appendChild(group);
    });
}

function renderRegisteredIngredientsTable() {
    const headerRow = document.getElementById("mgmt-table-header");
    const tbody = document.getElementById("mgmt-table-body");
    if (!headerRow || !tbody) return;
    
    clearElement(headerRow);
    const dragTh = document.createElement("th");
    dragTh.style.width = "45px";
    dragTh.style.textAlign = "center";
    dragTh.textContent = "이동";
    headerRow.appendChild(dragTh);

    ["카테고리", "재료명", "약어"].forEach(label => {
        headerRow.appendChild(createTextElement("th", "", label));
    });
    state.locations.forEach(loc => {
        const th = document.createElement("th");
        th.textContent = loc.name;
        headerRow.appendChild(th);
    });
    const sauceTh = document.createElement("th");
    sauceTh.textContent = "소스관리";
    headerRow.appendChild(sauceTh);

    const actTh = document.createElement("th");
    actTh.textContent = "동작";
    headerRow.appendChild(actTh);
    
    clearElement(tbody);
    
    state.ingredients.sort((a, b) => {
        const orderA = a.sort_order || a.sortOrder || 0;
        const orderB = b.sort_order || b.sortOrder || 0;
        if (orderA > 0 && orderB > 0 && orderA !== orderB) return orderA - orderB;
        const catCmp = (a.category || "").localeCompare(b.category || "", "ko-KR");
        if (catCmp !== 0) return catCmp;
        return (a.name || "").localeCompare(b.name || "", "ko-KR");
    });

    const query = (state.filters.mgmtSearch || "").trim().toLowerCase();
    const queryChosung = getChosung(query);
    const filteredIngredients = state.ingredients.filter(ing => {
        if (!query) return true;
        const name = (ing.name || "").toLowerCase();
        const nameChosung = getChosung(name);
        const category = (ing.category || "").toLowerCase();
        const abbr = (ing.abbr || "").toLowerCase();
        return name.includes(query) || 
               nameChosung.includes(queryChosung) || 
               category.includes(query) || 
               abbr.includes(query);
    });

    filteredIngredients.forEach((ing, index) => {
        const tr = document.createElement("tr");
        tr.draggable = true;
        tr.dataset.index = index;
        tr.style.cursor = "move";

        // Drag Handle Cell
        const dragTd = document.createElement("td");
        dragTd.style.textAlign = "center";
        dragTd.innerHTML = `<span style="cursor:grab; font-size:1.1rem; color: #38bdf8; user-select:none;" title="드래그하여 순서 변경">☰</span>`;
        tr.appendChild(dragTd);

        // Drag Events
        tr.addEventListener("dragstart", (e) => {
            tr.style.opacity = "0.5";
            tr.classList.add("dragging-row");
            e.dataTransfer.effectAllowed = "move";
            e.dataTransfer.setData("text/plain", index.toString());
        });

        tr.addEventListener("dragend", () => {
            tr.style.opacity = "1";
            tr.classList.remove("dragging-row");
            document.querySelectorAll("#mgmt-table-body tr").forEach(r => {
                r.style.borderTop = "";
                r.style.borderBottom = "";
            });
        });

        tr.addEventListener("dragover", (e) => {
            e.preventDefault();
            e.dataTransfer.dropEffect = "move";
            tr.style.borderTop = "2px dashed #38bdf8";
        });

        tr.addEventListener("dragleave", () => {
            tr.style.borderTop = "";
            tr.style.borderBottom = "";
        });

        tr.addEventListener("drop", async (e) => {
            e.preventDefault();
            tr.style.borderTop = "";
            tr.style.borderBottom = "";
            
            const fromIdxStr = e.dataTransfer.getData("text/plain");
            const fromIdx = parseInt(fromIdxStr, 10);
            const toIdx = index;

            if (!isNaN(fromIdx) && fromIdx !== toIdx && fromIdx >= 0 && fromIdx < filteredIngredients.length) {
                const movedItem = filteredIngredients[fromIdx];
                filteredIngredients.splice(fromIdx, 1);
                filteredIngredients.splice(toIdx, 0, movedItem);

                const newOrderNames = filteredIngredients.map(i => i.name);
                try {
                    await apiPost('/api/ingredients/reorder', { order: newOrderNames });
                    await loadAllData();
                    renderRegisteredIngredientsTable();
                    renderIngredients();
                } catch (err) {
                    alert("순서 변경 실패: " + err.message);
                }
            }
        });

        const categoryCell = document.createElement("td");
        const categoryTag = createTextElement("strong", "cat-tag", ing.category);
        categoryTag.style.cssText = "background: rgba(255,255,255,0.05); color: var(--text-primary); border: 1px solid var(--card-border);";
        categoryCell.appendChild(categoryTag);
        tr.appendChild(categoryCell);

        tr.appendChild(createTextElement("td", "", ing.name));
        tr.appendChild(createTextElement("td", "", ing.abbr || "-"));

        state.locations.forEach(loc => {
            const shelfDays = ing.storage && ing.storage[loc.name] ? ing.storage[loc.name].days : null;
            let valText = "-";
            if (shelfDays !== null) {
                if (loc.unit === "hour") {
                    if (loc.name === "분할" && shelfDays === 22) {
                        valText = "당일 22시";
                    } else {
                        valText = `${shelfDays}시간`;
                    }
                } else {
                    valText = `${shelfDays}일`;
                }
            }
            tr.appendChild(createTextElement("td", "", valText));
        });

        const sauceCell = document.createElement("td");
        sauceCell.style.textAlign = "center";
        const sauceChk = document.createElement("input");
        sauceChk.type = "checkbox";
        sauceChk.checked = !!(ing.is_sauce || ing.isSauce);
        sauceChk.style.cssText = "width: 18px; height: 18px; cursor: pointer; accent-color: #38bdf8;";
        sauceChk.title = "체크 시 소스관리 탭에서 사용 가능";
        sauceChk.addEventListener("change", async () => {
            const is_sauce = sauceChk.checked ? 1 : 0;
            try {
                const storagePayload = {};
                if (ing.storage) {
                    Object.entries(ing.storage).forEach(([locName, obj]) => {
                        const loc = state.locations.find(l => l.name === locName);
                        if (loc && obj && obj.days !== undefined && obj.days !== null) {
                            storagePayload[loc.id] = obj.days;
                        }
                    });
                }
                await apiPut(`/api/ingredients/${encodeURIComponent(ing.name)}`, {
                    name: ing.name,
                    category: ing.category,
                    abbr: ing.abbr || "",
                    is_sauce: is_sauce,
                    storage: storagePayload
                });
                await loadAllData();
                renderRegisteredIngredientsTable();
                renderIngredients();
            } catch (err) {
                alert("소스관리 설정 변경 실패: " + err.message);
                sauceChk.checked = !sauceChk.checked;
            }
        });
        sauceCell.appendChild(sauceChk);
        tr.appendChild(sauceCell);

        const actionCell = document.createElement("td");
        
        const upBtn = document.createElement("button");
        upBtn.className = "db-action-btn edit";
        upBtn.title = "한 칸 위로";
        upBtn.innerHTML = "▲";
        upBtn.style.cssText = "padding:2px 6px; font-size:0.75rem; margin-right:4px;";
        upBtn.addEventListener("click", async () => {
            const idx = state.ingredients.findIndex(i => i.name === ing.name);
            if (idx > 0) {
                const temp = state.ingredients[idx];
                state.ingredients[idx] = state.ingredients[idx - 1];
                state.ingredients[idx - 1] = temp;
                const orderNames = state.ingredients.map(i => i.name);
                try {
                    await apiPost('/api/ingredients/reorder', { order: orderNames });
                    await loadAllData();
                    renderRegisteredIngredientsTable();
                    renderIngredients();
                } catch (e) {
                    alert('순서 변경 실패: ' + e.message);
                }
            }
        });
        actionCell.appendChild(upBtn);

        const downBtn = document.createElement("button");
        downBtn.className = "db-action-btn edit";
        downBtn.title = "한 칸 아래로";
        downBtn.innerHTML = "▼";
        downBtn.style.cssText = "padding:2px 6px; font-size:0.75rem; margin-right:4px;";
        downBtn.addEventListener("click", async () => {
            const idx = state.ingredients.findIndex(i => i.name === ing.name);
            if (idx >= 0 && idx < state.ingredients.length - 1) {
                const temp = state.ingredients[idx];
                state.ingredients[idx] = state.ingredients[idx + 1];
                state.ingredients[idx + 1] = temp;
                const orderNames = state.ingredients.map(i => i.name);
                try {
                    await apiPost('/api/ingredients/reorder', { order: orderNames });
                    await loadAllData();
                    renderRegisteredIngredientsTable();
                    renderIngredients();
                } catch (e) {
                    alert('순서 변경 실패: ' + e.message);
                }
            }
        });
        actionCell.appendChild(downBtn);

        const editBtn = document.createElement("button");
        editBtn.className = "db-action-btn edit";
        editBtn.dataset.name = ing.name;
        editBtn.title = "수정";
        const editIcon = document.createElement("i");
        editIcon.dataset.lucide = "edit-3";
        editIcon.style.cssText = "width:14px;height:14px;";
        editBtn.appendChild(editIcon);
        editBtn.addEventListener("click", () => {
            openEditModal(ing.name);
        });
        actionCell.appendChild(editBtn);

        const deleteBtn = document.createElement("button");
        deleteBtn.className = "db-action-btn delete";
        deleteBtn.dataset.name = ing.name;
        deleteBtn.title = "삭제";
        const icon = document.createElement("i");
        icon.dataset.lucide = "trash-2";
        icon.style.cssText = "width:14px;height:14px;";
        deleteBtn.appendChild(icon);
        deleteBtn.addEventListener("click", () => {
            deleteIngredient(ing.name);
        });
        actionCell.appendChild(deleteBtn);
        tr.appendChild(actionCell);
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
    const unitSelect = document.getElementById("new-loc-unit");
    const name = nameInput.value.trim();
    const unit = unitSelect ? unitSelect.value : "day";
    
    if (state.locations.some(l => l.name === name)) {
        alert("이미 존재하는 보관위치입니다.");
        return;
    }
    
    try {
        await apiPost("/api/storage-locations", { name, unit });
        state.locations = await apiGet("/api/storage-locations");
        renderLocationChips();
        renderStorageFieldsInForm();
        renderRegisteredIngredientsTable();
        
        nameInput.value = "";
        if (unitSelect) unitSelect.value = "day";
    } catch (err) {
        alert("보관위치 추가 실패: " + err.message);
    }
}

async function handleMgmtAddIngredient(e) {
    e.preventDefault();
    const nameInput = document.getElementById("mgmt-new-name");
    const abbrInput = document.getElementById("mgmt-new-abbr");
    const categorySelect = document.getElementById("mgmt-new-category");
    const isSauceInp = document.getElementById("mgmt-new-is-sauce");
    
    const name = nameInput.value.trim();
    const abbr = abbrInput.value.trim().toUpperCase();
    const category = categorySelect.value;
    const is_sauce = isSauceInp ? (isSauceInp.checked ? 1 : 0) : 0;
    
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
            // Send a plain integer (matching the edit/PUT handler and the server
            // contract). Wrapping it as { days } made the server reject it as
            // "양의 정수여야 합니다".
            storage[locId] = parseInt(val);
        }
    });
    
    try {
        await apiPost("/api/ingredients", { name, category, abbr, is_sauce, storage });
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
                    clearElement(storageOptionsContainer);
                }
            }
        } catch (err) {
            alert("재료 삭제 실패: " + err.message);
        }
    }
}

function openEditModal(name) {
    const ingredient = state.ingredients.find(i => i.name === name);
    if (!ingredient) return;

    editOldNameInput.value = name;
    editNameInput.value = name;
    editAbbrInput.value = ingredient.abbr || "";
    
    const editIsSauceInp = document.getElementById("mgmt-edit-is-sauce");
    if (editIsSauceInp) editIsSauceInp.checked = !!(ingredient.is_sauce || ingredient.isSauce);

    clearElement(editCategorySelect);
    state.categories.forEach(cat => {
        const opt = document.createElement("option");
        opt.value = cat.name;
        opt.textContent = `${cat.emoji ? cat.emoji + ' ' : ''}${cat.name}`;
        if (cat.name === ingredient.category) {
            opt.selected = true;
        }
        editCategorySelect.appendChild(opt);
    });

    clearElement(editStorageFieldsContainer);
    if (state.locations.length === 0) {
        const emptyState = createTextElement("div", "", "등록된 보관위치가 없습니다.");
        emptyState.style.cssText = "grid-column:1/-1; text-align:center; padding:10px; color:var(--text-muted); font-size:0.82rem;";
        editStorageFieldsContainer.appendChild(emptyState);
    } else {
        state.locations.forEach(loc => {
            const shelfDays = ingredient.storage && ingredient.storage[loc.name] ? ingredient.storage[loc.name].days : "";

            const group = document.createElement("div");
            group.className = "storage-field-group";
            group.appendChild(createTextElement("label", "", loc.name));

            const wrapper = document.createElement("div");
            wrapper.className = "storage-field-input-wrapper";
            const input = document.createElement("input");
            input.type = "number";
            input.className = "mgmt-edit-storage-input";
            input.dataset.locId = loc.id;
            input.min = "1";
            const isHourUnit = loc.unit === "hour";
            input.placeholder = isHourUnit ? "기한(시간)" : "기한(일)";
            input.value = shelfDays;
            wrapper.appendChild(input);

            const unit = createTextElement("span", "", isHourUnit ? "시간" : "일");
            unit.style.cssText = "font-size:0.75rem; color:var(--text-muted);";
            wrapper.appendChild(unit);
            group.appendChild(wrapper);
            editStorageFieldsContainer.appendChild(group);
        });
    }

    editIngredientModal.style.display = "flex";
    document.body.classList.add("modal-open");
    lucide.createIcons();
}

function closeEditModal() {
    editIngredientModal.style.display = "none";
    document.body.classList.remove("modal-open");
}

async function handleMgmtEditIngredient(e) {
    e.preventDefault();
    const oldName = editOldNameInput.value;
    const name = editNameInput.value.trim();
    const abbr = editAbbrInput.value.trim().toUpperCase();
    const category = editCategorySelect.value;
    const editIsSauceInp = document.getElementById("mgmt-edit-is-sauce");
    const is_sauce = editIsSauceInp ? (editIsSauceInp.checked ? 1 : 0) : 0;

    if (!name || !category) {
        alert("재료명과 카테고리는 필수 항목입니다.");
        return;
    }

    const storage = {};
    const storageInputs = document.querySelectorAll(".mgmt-edit-storage-input");
    storageInputs.forEach(inp => {
        const locId = inp.dataset.locId;
        const val = inp.value.trim();
        if (val !== "") {
            storage[locId] = parseInt(val);
        }
    });

    try {
        await apiPut(`/api/ingredients/${encodeURIComponent(oldName)}`, { category, name, abbr, is_sauce, storage });
        
        // If selected ingredient was renamed, update selectedId
        if (state.selectedId === oldName) {
            state.selectedId = name;
        }

        await loadAllData();
        renderRegisteredIngredientsTable();
        renderIngredients();
        
        // Update selected details if selected item was modified
        if (state.selectedId === name) {
            const updated = state.ingredients.find(i => i.name === name);
            if (updated) {
                // Adjust selected storage if it's no longer available
                const availableLocations = updated.storage ? Object.keys(updated.storage) : [];
                if (state.selectedStorage && !availableLocations.includes(state.selectedStorage) && state.selectedStorage !== "입고") {
                    state.selectedStorage = availableLocations.length > 0 ? availableLocations[0] : "입고";
                }
                renderStorageOptions(updated);
                updateStickerPreview();
            }
        }

        closeEditModal();
    } catch (err) {
        alert("재료 수정 실패: " + err.message);
    }
}

async function handleResetDatabase() {
    if (confirm("정말로 모든 설정을 기본값으로 리셋하시겠습니까?\n직접 추가하거나 수정한 카테고리, 보관위치, 재료, 라벨 규격이 전부 삭제됩니다.")) {
        try {
            await apiPost("/api/ingredients/reset", {});
            await reloadAndRenderMainViews();

            if (state.ingredients.length > 0) {
                selectIngredient(state.ingredients[0].name);
            } else {
                state.selectedId = null;
                state.selectedStorage = null;
                selectedIngDisplay.textContent = "재료를 선택해 주세요";
                clearElement(storageOptionsContainer);
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

function formatShortDate(date) {
    const yy = String(date.getFullYear()).slice(-2);
    const mm = String(date.getMonth() + 1).padStart(2, '0');
    const dd = String(date.getDate()).padStart(2, '0');
    const hh = String(date.getHours()).padStart(2, '0');
    const min = String(date.getMinutes()).padStart(2, '0');
    return `${yy}.${mm}.${dd} ${hh}:${min}`;
}

function updateStickerPreview() {
    const ingredient = state.ingredients.find(i => i.name === state.selectedId);
    if (!ingredient) return;
    
    // 1. Support legacy layout elements with safety checks
    if (stickerAbbr) {
        if (ingredient.abbr) {
            stickerAbbr.textContent = ingredient.abbr;
            stickerAbbr.style.display = "flex";
        } else {
            stickerAbbr.style.display = "none";
        }
    }
    
    if (stickerName) {
        stickerName.textContent = ingredient.name;
    }
    
    const stickerPrepLabel = document.getElementById("sticker-prep-label");
    const expireRow = document.querySelector(".expire-date-row");
    let shelfLifeValue = 0;
    if (state.selectedStorage && ingredient.storage && ingredient.storage[state.selectedStorage]) {
        shelfLifeValue = ingredient.storage[state.selectedStorage].days || 0;
    }
    
    const loc = state.locations.find(l => l.name === state.selectedStorage);
    const isHourUnit = loc ? loc.unit === "hour" : (state.selectedStorage === "소스보틀" || state.selectedStorage === "분할");

    let expireTime;
    if (isHourUnit) {
        if (state.selectedStorage === "분할" && shelfLifeValue === 22) {
            expireTime = new Date(state.prepTime);
            expireTime.setHours(22, 0, 0, 0);
        } else {
            expireTime = new Date(state.prepTime.getTime() + shelfLifeValue * 60 * 60000);
        }
    } else {
        expireTime = new Date(state.prepTime.getTime() + shelfLifeValue * 24 * 60 * 60000);
    }

    if (state.selectedStorage === "입고") {
        if (stickerLoc) stickerLoc.textContent = "입고";
        if (stickerPrepLabel) stickerPrepLabel.textContent = "입고 :";
        if (stickerPrepDate) stickerPrepDate.textContent = formatShortDate(state.prepTime);
        if (expireRow) expireRow.style.display = "none";
    } else {
        if (stickerLoc) stickerLoc.textContent = state.selectedStorage ? state.selectedStorage : "보관위치 미지정";
        if (stickerPrepLabel) stickerPrepLabel.textContent = "준비일시:";
        if (stickerPrepDate) stickerPrepDate.textContent = formatDate(state.prepTime);
        if (expireRow) expireRow.style.display = "block";
        if (stickerExpireDate) stickerExpireDate.textContent = formatDate(expireTime);
    }
    
    if (stickerStaffVal) {
        stickerStaffVal.textContent = state.staffName ? state.staffName : "-";
    }

    // 2. Support new 4-line layout if present (no crash if absent)
    if (stickerLine1) {
        const storageDisplay = state.selectedStorage || "";
        const abbrText = ingredient.abbr ? ` (${ingredient.abbr})` : "";
        stickerLine1.textContent = `[${storageDisplay}] ${ingredient.name}${abbrText}`;
    }
    if (stickerLine2) {
        const line2Prefix = state.selectedStorage === "입고" ? "입고" : "준비";
        stickerLine2.textContent = `${line2Prefix}: ${formatDate(state.prepTime)}`;
    }
    if (stickerLine3) {
        if (state.selectedStorage === "입고") {
            stickerLine3.textContent = "";
        } else {
            stickerLine3.textContent = `폐기: ${formatDate(expireTime)}`;
        }
    }
    if (stickerLine4) {
        stickerLine4.textContent = `(담당: ${state.staffName || "-"})`;
    }
    applyLayoutSettings();
}

// ==========================================
// Print Operation
// ==========================================
function triggerPrint() {
    const quantity = state.printQty;
    clearElement(printStickerContainer);

    // Label size is fixed at 55×20mm
    const w = FIXED_LABEL_W;
    const h = FIXED_LABEL_H;
    
    const scale = 6.4;
    const mmTop = (state.layout.topPadding / scale).toFixed(2);
    const mmLeft = (state.layout.leftPadding / scale).toFixed(2);
    const mmRight = (state.layout.rightPadding / scale).toFixed(2);
    const mmBottom = (state.layout.bottomPadding / scale).toFixed(2);
    const mmGap = (state.layout.verticalGap / scale).toFixed(2);

    let printStyle = document.getElementById("dynamic-print-style");
    if (!printStyle) {
        printStyle = document.createElement("style");
        printStyle.id = "dynamic-print-style";
        document.head.appendChild(printStyle);
    }
    printStyle.textContent = `
        @page {
            size: ${w}mm ${h}mm;
            margin: 0;
        }
        .print-only-container .sticker-preview-content {
            width: ${w}mm !important;
            height: ${h}mm !important;
            /* Override the screen-preview min sizes (px) — min-width/height beat
               width/height regardless of !important, which previously inflated
               the printed label to screen-pixel dimensions. */
            min-width: ${w}mm !important;
            min-height: ${h}mm !important;
            max-width: ${w}mm !important;
            max-height: ${h}mm !important;
            padding: ${mmTop}mm ${mmRight}mm ${mmBottom}mm ${mmLeft}mm !important;
            gap: ${mmGap}mm !important;
            display: flex !important;
            flex-direction: column !important;
            justify-content: center !important;
            align-items: flex-start !important;
            box-sizing: border-box !important;
        }
        .print-only-container #sticker-line-1 {
            font-size: ${state.layout.showLine1 ? (state.layout.sizeLine1 * 2.5).toFixed(2) : 0}mm !important;
            display: ${state.layout.showLine1 ? 'block' : 'none'} !important;
            line-height: 1.15 !important;
            font-weight: 700 !important;
            color: #000000 !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
            white-space: nowrap !important;
            width: 100% !important;
            text-align: left !important;
        }
        .print-only-container #sticker-line-2 {
            font-size: ${state.layout.showLine2 ? (state.layout.sizeLine2 * 2.5).toFixed(2) : 0}mm !important;
            display: ${state.layout.showLine2 ? 'block' : 'none'} !important;
            line-height: 1.15 !important;
            font-weight: 700 !important;
            color: #000000 !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
            white-space: nowrap !important;
            width: 100% !important;
            text-align: left !important;
        }
        .print-only-container #sticker-line-3 {
            font-size: ${state.layout.showLine3 ? (state.layout.sizeLine3 * 2.5).toFixed(2) : 0}mm !important;
            display: ${state.layout.showLine3 ? 'block' : 'none'} !important;
            line-height: 1.15 !important;
            font-weight: 700 !important;
            color: #000000 !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
            white-space: nowrap !important;
            width: 100% !important;
            text-align: left !important;
        }
        .print-only-container #sticker-line-4 {
            font-size: ${state.layout.showLine4 ? (state.layout.sizeLine4 * 2.5).toFixed(2) : 0}mm !important;
            display: ${state.layout.showLine4 ? 'block' : 'none'} !important;
            line-height: 1.15 !important;
            font-weight: 700 !important;
            color: #555555 !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
            white-space: nowrap !important;
            width: 100% !important;
            text-align: left !important;
        }
    `;
    
    const previewContent = document.getElementById("sticker-preview").cloneNode(true);
    previewContent.removeAttribute("id");
    
    for (let i = 0; i < quantity; i++) {
        const item = previewContent.cloneNode(true);
        printStickerContainer.appendChild(item);
    }
    
    if (document.fonts && document.fonts.ready) {
        document.fonts.ready.then(() => {
            window.print();
        }).catch(() => {
            window.print();
        });
    } else {
        window.print();
    }
}

// ==========================================
// Settings Modal & Access Denied Modal
// ==========================================
async function openSettingsModal() {
    settingsModal.style.display = "flex";
    document.body.classList.add("modal-open");

    // Load current client IP and Admin Allowed IP settings
    try {
        const ipRes = await apiGet('/api/client-ip');
        const displayEl = document.getElementById("current-client-ip-display");
        if (displayEl) {
            displayEl.textContent = `현재 접속 IP: ${ipRes.ip || '알 수 없음'}`;
            displayEl.dataset.clientIp = ipRes.ip || '';
        }

        const settingsRes = await apiGet('/api/system-settings');
        const inputEl = document.getElementById("admin-allowed-ips-input");
        if (inputEl && settingsRes.settings) {
            inputEl.value = settingsRes.settings.admin_allowed_ips || "";
        }
    } catch (e) {
        console.error("Failed to load admin IP settings:", e);
    }
}

function closeSettingsModal() {
    settingsModal.style.display = "none";
    document.body.classList.remove("modal-open");
}

function showAccessDeniedModal(msg, clientIp) {
    const modal = document.getElementById("access-denied-modal");
    const msgEl = document.getElementById("access-denied-msg");
    const ipEl = document.getElementById("access-denied-client-ip");
    if (modal) {
        if (msgEl && msg) msgEl.innerHTML = msg.replace(/\n/g, "<br>");
        if (ipEl) ipEl.textContent = clientIp || "알 수 없음";
        modal.style.display = "flex";
        if (window.lucide) window.lucide.createIcons();
    }
}

function closeAccessDeniedModal() {
    const modal = document.getElementById("access-denied-modal");
    if (modal) modal.style.display = "none";
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

// ==========================================
// Authentication Logic & Helpers
// ==========================================
async function checkAuthStatus() {
    try {
        const status = await apiGet('/api/auth/status');
        if (status.loggedIn) {
            state.user = status.user;
            loginOverlay.style.display = "none";
            logoutBtn.style.display = "flex";
            
            applyRoleRestrictions();
            await reloadAndRenderMainViews();
            
            if (state.ingredients.length > 0) {
                selectIngredient(state.ingredients[0].name);
            }
        } else {
            state.user = null;
            loginOverlay.style.display = "flex";
            logoutBtn.style.display = "none";
        }
    } catch (e) {
        console.error("Auth check failed:", e);
        loginOverlay.style.display = "flex";
        logoutBtn.style.display = "none";
    }
}

function applyRoleRestrictions() {
    const manageTabBtn = document.querySelector('.main-tab[data-tab="tab-manage"]');
    if (!state.user) return;
    
    if (state.user.role === 'admin') {
        if (settingsOpenBtn) settingsOpenBtn.style.display = "flex";
        if (manageTabBtn) manageTabBtn.style.display = "flex";
    } else {
        // Staff role restrictions
        if (settingsOpenBtn) settingsOpenBtn.style.display = "none";
        if (manageTabBtn) manageTabBtn.style.display = "none";
        
        // Force to Print Tab
        state.activeTab = "tab-print";
        document.querySelectorAll(".main-tab").forEach(t => {
            if (t.dataset.tab === "tab-print") t.classList.add("active");
            else t.classList.remove("active");
        });
        document.querySelectorAll(".tab-content").forEach(c => {
            if (c.id === "tab-print") c.classList.add("active");
            else c.classList.remove("active");
        });
    }
}

async function handleLogin(e) {
    e.preventDefault();
    loginErrorMsg.style.display = "none";
    
    const username = loginUsernameInput.value.trim();
    const password = loginPasswordInput.value;
    
    if (!username || !password) {
        showLoginError("아이디와 비밀번호를 모두 입력해 주세요.");
        return;
    }
    
    try {
        const response = await apiPost('/api/auth/login', { username, password });
        if (response.success) {
            state.user = response.user;
            loginUsernameInput.value = "";
            loginPasswordInput.value = "";
            loginOverlay.style.display = "none";
            logoutBtn.style.display = "flex";
            
            applyRoleRestrictions();
            await reloadAndRenderMainViews();
            
            if (state.ingredients.length > 0) {
                selectIngredient(state.ingredients[0].name);
            }
            lucide.createIcons();
        }
    } catch (err) {
        showLoginError(err.message || "로그인 요청에 실패했습니다.");
    }
}

function showLoginError(msg) {
    loginErrorMsg.textContent = msg;
    loginErrorMsg.style.display = "block";
}

async function handleLogout() {
    if (!confirm("로그아웃 하시겠습니까?")) return;
    try {
        await apiPost('/api/auth/logout', {});
        state.user = null;
        loginOverlay.style.display = "flex";
        logoutBtn.style.display = "none";
        
        // Reset state
        state.ingredients = [];
        state.categories = [];
        state.locations = [];
        state.selectedId = null;
        state.selectedStorage = null;

        if (ingredientsGrid) clearElement(ingredientsGrid);
        if (selectedIngDisplay) selectedIngDisplay.textContent = "재료를 선택해 주세요";
        if (storageOptionsContainer) clearElement(storageOptionsContainer);
    } catch (e) {
        console.error("Logout failed:", e);
        state.user = null;
        loginOverlay.style.display = "flex";
        logoutBtn.style.display = "none";
    }
}

function initEmojiPicker() {
    const emojiInput = document.getElementById("new-cat-emoji");
    if (!emojiInput) return;

    // Prevent typing multiple characters/emojis; keep only the latest emoji
    emojiInput.addEventListener("input", () => {
        const value = emojiInput.value;
        const segments = Array.from(value);
        if (segments.length > 0) {
            // Keep the last valid emoji/char
            emojiInput.value = segments[segments.length - 1];
        }
    });

    // Make input look clickable and show helper tooltip
    emojiInput.style.cursor = "pointer";
    emojiInput.title = "클릭하여 이모지 선택";

    // Create wrapper & popover dynamically
    const wrapper = document.createElement("div");
    wrapper.className = "emoji-input-wrapper";
    emojiInput.parentNode.insertBefore(wrapper, emojiInput);
    wrapper.appendChild(emojiInput);

    const popover = document.createElement("div");
    popover.id = "emoji-picker-popover";
    popover.className = "emoji-picker-popover";
    popover.style.display = "none";

    const EMOJIS = [
        "❌", "🥬", "🥦", "🥕", "🧅", "🍄", "🍅", 
        "🍖", "🥩", "🍗", "🥓", "🧀", "🥫", 
        "🏺", "🍕", "🍞", "🥚", "🥛", "🧈", 
        "🦐", "🐟", "🍇", "🍓", "🍋", "🍍", 
        "🍯", "🧂", "🍟", "☕", "🥤", "🧴"
    ];

    EMOJIS.forEach(emoji => {
        const item = document.createElement("span");
        item.className = "emoji-picker-item";
        item.textContent = emoji;
        // Tooltip for clear option
        if (emoji === "❌") {
            item.title = "이모지 없음 (지우기)";
        }
        item.addEventListener("click", (e) => {
            e.stopPropagation();
            if (emoji === "❌") {
                emojiInput.value = "";
            } else {
                emojiInput.value = emoji;
            }
            popover.style.display = "none";
            // Dispatch input event to trigger any validation or input handling
            emojiInput.dispatchEvent(new Event("input"));
        });
        popover.appendChild(item);
    });

    wrapper.appendChild(popover);

    // Toggle popover on click
    emojiInput.addEventListener("click", (e) => {
        e.stopPropagation();
        popover.style.display = popover.style.display === "none" ? "grid" : "none";
    });

    // Close popover when clicking outside
    document.addEventListener("click", (e) => {
        if (!wrapper.contains(e.target)) {
            popover.style.display = "none";
        }
    });
}

// ==========================================
// Pizza Sauce Smart Labeling System
// ==========================================
let sauceState = {
    db: [],
    selectedId: null,
    sequence: 1,
    systemTime: new Date(),
    lastPrintedSauce: null,
    lastPrintedRawOutTime: null
};

function initSauceSystem() {
    loadSauceFromLocalStorage();
    sauceState.systemTime = new Date();
    updateSauceSystemTimeDisplay();
    updateSauceUI();

    setInterval(tickSauceTimer, 1000);

    const barcodeInput = document.getElementById("sauce-barcode-input");
    if (barcodeInput) {
        barcodeInput.addEventListener("keypress", (e) => {
            if (e.key === "Enter") {
                handleSauceBarcodeInput();
            }
        });
    }

    const btnPrep = document.getElementById("sauce-btn-prep");
    if (btnPrep) btnPrep.addEventListener("click", triggerSaucePrep);

    const btnIn = document.getElementById("sauce-btn-in");
    if (btnIn) btnIn.addEventListener("click", triggerSauceIn);

    const btnOut = document.getElementById("sauce-btn-out");
    if (btnOut) btnOut.addEventListener("click", triggerSauceOut);

    const printRawBtn = document.getElementById("sauce-print-raw-btn");
    if (printRawBtn) printRawBtn.addEventListener("click", printSauceLabelRaw);

    const resetAllBtn = document.getElementById("sauce-reset-all-btn");
    if (resetAllBtn) resetAllBtn.addEventListener("click", resetSauceAllData);
}

function loadSauceFromLocalStorage() {
    const saved = localStorage.getItem("sauce_db");
    if (saved) {
        try {
            sauceState.db = JSON.parse(saved);
            sauceState.db.forEach(item => {
                if (item.Prep_Time) item.Prep_Time = new Date(item.Prep_Time);
                if (item.Last_Action_Time) item.Last_Action_Time = new Date(item.Last_Action_Time);
                if (item.Est_Discard_Time) item.Est_Discard_Time = new Date(item.Est_Discard_Time);
            });
        } catch (_) {}
    }
    const savedSeq = localStorage.getItem("sauce_seq");
    if (savedSeq) {
        sauceState.sequence = parseInt(savedSeq, 10) || 1;
    }
}

function saveSauceToLocalStorage() {
    localStorage.setItem("sauce_db", JSON.stringify(sauceState.db));
    localStorage.setItem("sauce_seq", sauceState.sequence.toString());
}

function tickSauceTimer() {
    sauceState.systemTime = new Date();
    updateSauceSystemTimeDisplay();
    checkSauceExpirations();
    if (state.activeTab === "tab-sauce") {
        updateSauceUI();
    }
}

function updateSauceSystemTimeDisplay() {
    const el = document.getElementById("sauce-current-system-time");
    if (el) {
        el.innerText = formatSauceDateTime(sauceState.systemTime);
    }
}

function formatSauceDateTime(date) {
    if (!date) return "-";
    const yy = String(date.getFullYear()).slice(2);
    const mm = String(date.getMonth() + 1).padStart(2, "0");
    const dd = String(date.getDate()).padStart(2, "0");
    const hh = String(date.getHours()).padStart(2, "0");
    const min = String(date.getMinutes()).padStart(2, "0");
    const sec = String(date.getSeconds()).padStart(2, "0");
    return `${yy}-${mm}-${dd} ${hh}:${min}:${sec}`;
}

function formatSauceDateTimeShort(date) {
    if (!date) return "-";
    const yy = String(date.getFullYear()).slice(2);
    const mm = String(date.getMonth() + 1).padStart(2, "0");
    const dd = String(date.getDate()).padStart(2, "0");
    const hh = String(date.getHours()).padStart(2, "0");
    const min = String(date.getMinutes()).padStart(2, "0");
    return `${yy}-${mm}-${dd} ${hh}:${min}`;
}

function formatSauceDateTimeWithDay(date) {
    if (!date) return "-";
    const days = ["일", "월", "화", "수", "목", "금", "토"];
    const dayName = days[date.getDay()];
    return `${formatSauceDateTimeShort(date)} (${dayName})`;
}

function formatSauceDuration(totalMin) {
    if (totalMin <= 0) return "00시간 00분";
    const hrs = Math.floor(totalMin / 60);
    const mins = Math.floor(totalMin % 60);
    return `${String(hrs).padStart(2, "0")}시간 ${String(mins).padStart(2, "0")}분`;
}

function formatSauceDurationLabel(totalMin) {
    if (totalMin <= 0) return "00:00";
    const hrs = Math.floor(totalMin / 60);
    const mins = Math.floor(totalMin % 60);
    return `${String(hrs).padStart(2, "0")}:${String(mins).padStart(2, "0")}`;
}

function checkSauceExpirations() {
    let changed = false;
    const now = sauceState.systemTime;
    const cutoff24h = new Date(now.getTime() - 24 * 60 * 60 * 1000);

    const initialLen = sauceState.db.length;
    sauceState.db = sauceState.db.filter(item => {
        const prep = new Date(item.Prep_Time || item.Last_Action_Time);
        const last = new Date(item.Last_Action_Time);
        if (prep < cutoff24h || last < cutoff24h) return false;
        return true;
    });
    if (sauceState.db.length !== initialLen) changed = true;

    sauceState.db.forEach(item => {
        if (item.Status === "DISCARD") return;
        let remMin = item.Rem_Valid_Min;
        if (item.Status === "PREP" || item.Status === "OUT") {
            const lastAction = new Date(item.Last_Action_Time);
            let elapsedMin = 0;
            if (sauceState.systemTime > lastAction) {
                elapsedMin = (sauceState.systemTime - lastAction) / (1000 * 60);
            }
            remMin = item.Total_Valid_Min - item.Accum_Used_Min - elapsedMin;
            if (remMin <= 0 || sauceState.systemTime >= item.Est_Discard_Time) {
                item.Status = "DISCARD";
                item.Rem_Valid_Min = 0;
                item.Accum_Used_Min = item.Total_Valid_Min;
                item.Est_Discard_Time = sauceState.systemTime;
                changed = true;
            }
        }
    });
    if (changed) saveSauceToLocalStorage();
}

function handleSauceBarcodeInput() {
    const input = document.getElementById("sauce-barcode-input");
    if (!input) return;
    const idVal = input.value.trim().toUpperCase();
    if (!idVal) return;
    const existing = sauceState.db.find(item => item.Source_ID === idVal);
    if (existing) {
        sauceState.selectedId = idVal;
        updateSauceUI();
        input.value = "";
    } else {
        triggerSaucePrep();
    }
}

function triggerSaucePrep() {
    const input = document.getElementById("sauce-barcode-input");
    const sauceSelect = document.getElementById("sauce-product-select");
    const selectedSauceName = sauceSelect ? sauceSelect.value : "피자소스";
    
    const ing = state.ingredients.find(i => i.name === selectedSauceName);
    let validMin = 600;
    let sauceCode = "S";
    let sauceName = selectedSauceName || "피자소스";

    if (ing) {
        if (ing.abbr) sauceCode = ing.abbr.toUpperCase();
        if (ing.storage && ing.storage["소스보틀"] && ing.storage["소스보틀"].days > 0) {
            validMin = ing.storage["소스보틀"].days * 60;
        } else if (ing.storage) {
            const foundLoc = Object.entries(ing.storage).find(([k, v]) => (k.includes("소스") || k.includes("보틀")) && v.days > 0);
            if (foundLoc) validMin = foundLoc[1].days * 60;
        }
    }

    let sourceId = input ? input.value.trim().toUpperCase() : "";
    if (!sourceId) {
        const yy = String(sauceState.systemTime.getFullYear()).slice(2);
        const mm = String(sauceState.systemTime.getMonth() + 1).padStart(2, "0");
        const dd = String(sauceState.systemTime.getDate()).padStart(2, "0");
        const prefix = `${sauceCode}${yy}${mm}${dd}-`;
        const todayCount = sauceState.db.filter(item => item.Source_ID && item.Source_ID.startsWith(prefix)).length;
        const seq = String(todayCount + 1).padStart(3, "0");
        sourceId = `${prefix}${seq}`;
    }

    if (sauceState.db.some(item => item.Source_ID === sourceId)) {
        alert("이미 존재하는 소스 ID입니다.");
        return;
    }

    const now = new Date(sauceState.systemTime);
    const estDiscard = new Date(now.getTime() + validMin * 60 * 1000);

    const newRecord = {
        Source_ID: sourceId,
        Sauce_Name: sauceName,
        sauceName: sauceName,
        Status: "PREP",
        Prep_Time: now,
        Total_Valid_Min: validMin,
        Accum_Used_Min: 0,
        Rem_Valid_Min: validMin,
        Last_Action_Time: now,
        Est_Discard_Time: estDiscard,
        _updated: true
    };

    sauceState.db.unshift(newRecord);
    sauceState.selectedId = sourceId;
    if (input) input.value = "";

    renderSaucePrintedLabel(newRecord);
    saveSauceToLocalStorage();
    updateSauceUI();
}

function getActiveOrSelectedSauce() {
    if (sauceState.selectedId) {
        return sauceState.db.find(item => item.Source_ID === sauceState.selectedId);
    }
    return sauceState.db.find(item => item.Status !== "DISCARD");
}

function triggerSauceIn() {
    const item = getActiveOrSelectedSauce();
    if (!item) {
        alert("냉장 보관할 소스를 선택하거나 ID를 입력하세요.");
        return;
    }
    if (item.Status === "DISCARD") {
        alert("폐기된 소스는 냉장 보관할 수 없습니다.");
        return;
    }
    if (item.Status === "IN") {
        alert("이미 냉장 보관 상태(IN)입니다.");
        return;
    }

    const now = new Date(sauceState.systemTime);
    const lastAction = new Date(item.Last_Action_Time);
    let workDuration = 0;
    if (now > lastAction) {
        workDuration = (now - lastAction) / (1000 * 60);
    }

    item.Accum_Used_Min = Math.min(item.Total_Valid_Min, item.Accum_Used_Min + workDuration);
    item.Rem_Valid_Min = Math.max(0, item.Total_Valid_Min - item.Accum_Used_Min);
    item.Last_Action_Time = now;
    item.Est_Discard_Time = null;
    item.Status = "IN";
    item._updated = true;

    renderSaucePrintedLabel(item);
    saveSauceToLocalStorage();
    updateSauceUI();
}

function triggerSauceOut() {
    const item = getActiveOrSelectedSauce();
    if (!item) {
        alert("냉장 출고할 소스를 선택하거나 ID를 입력하세요.");
        return;
    }
    if (item.Status === "DISCARD") {
        alert("폐기된 소스는 출고할 수 없습니다.");
        return;
    }
    if (item.Status === "PREP" || item.Status === "OUT") {
        alert("이미 실온 사용 상태(PREP/OUT)입니다.");
        return;
    }

    const now = new Date(sauceState.systemTime);
    const openTimeToday = new Date(sauceState.systemTime);
    openTimeToday.setHours(11, 0, 0, 0);

    let effectiveStart = new Date(now);
    if (now < openTimeToday) {
        effectiveStart = openTimeToday;
    }

    item.Last_Action_Time = effectiveStart;
    item.Est_Discard_Time = new Date(effectiveStart.getTime() + item.Rem_Valid_Min * 60 * 1000);
    item.Status = "OUT";
    item._updated = true;

    renderSaucePrintedLabel(item, now);
    saveSauceToLocalStorage();
    updateSauceUI();
}

function resetSauceAllData() {
    if (confirm("등록된 모든 소스 관리 이력을 초기화하시겠습니까?")) {
        sauceState.db = [];
        sauceState.selectedId = null;
        saveSauceToLocalStorage();
        updateSauceUI();
        const paper = document.getElementById("sauce-printer-paper-feed");
        const idleMsg = document.getElementById("sauce-printer-idle-msg");
        if (paper) paper.style.display = "none";
        if (idleMsg) idleMsg.style.display = "block";
    }
}

function renderSaucePrintedLabel(item, rawOutTime = null) {
    const paper = document.getElementById("sauce-printer-paper-feed");
    const idleMsg = document.getElementById("sauce-printer-idle-msg");
    if (!paper || !idleMsg) return;

    idleMsg.style.display = "none";
    paper.style.display = "flex";

    const remMin = item.Rem_Valid_Min;
    let html = "";

    if (item.Status === "PREP") {
        html = `
            <div class="label-2050">
                <div class="label-row label-header">
                    <span>PS 피자소스</span>
                    <span>[PREP]</span>
                </div>
                <div class="label-row"><span>ID: ${item.Source_ID}</span></div>
                <div class="label-row"><span>Prep: ${formatSauceDateTimeWithDay(item.Last_Action_Time)}</span></div>
                <div class="label-row"><span style="color: red;">폐기일: ${formatSauceDateTimeWithDay(item.Est_Discard_Time)}</span></div>
                <div class="label-row"><span>잔여: 시간 ${formatSauceDurationLabel(remMin)}</span></div>
            </div>
        `;
    } else if (item.Status === "IN") {
        const prepTime = item.Prep_Time || item.Last_Action_Time;
        html = `
            <div class="label-2050">
                <div class="label-row label-header">
                    <span>PS 피자소스</span>
                    <span>[IN]</span>
                </div>
                <div class="label-row"><span>ID: ${item.Source_ID}</span></div>
                <div class="label-row"><span>PREP: ${formatSauceDateTimeWithDay(prepTime)}</span></div>
                <div class="label-row"><span>IN  : ${formatSauceDateTimeWithDay(item.Last_Action_Time)}</span></div>
                <div class="label-row"><span style="color: blue;">※ 차감 중지</span></div>
                <div class="label-row"><span>잔여: 시간 ${formatSauceDurationLabel(remMin)}</span></div>
            </div>
        `;
    } else if (item.Status === "OUT") {
        const processTime = rawOutTime || item.Last_Action_Time || sauceState.systemTime;
        html = `
            <div class="label-2050">
                <div class="label-row label-header">
                    <span>PS 피자소스</span>
                    <span>[OUT]</span>
                </div>
                <div class="label-row"><span>ID: ${item.Source_ID}</span></div>
                <div class="label-row"><span>OUT : ${formatSauceDateTimeWithDay(processTime)}</span></div>
                <div class="label-row"><span style="color: red;">폐기: ${formatSauceDateTimeWithDay(item.Est_Discard_Time)}</span></div>
                <div class="label-row"><span>잔여: 시간 ${formatSauceDurationLabel(remMin)}</span></div>
            </div>
        `;
    }

    paper.innerHTML = html;
}

function printSauceLabelRaw() {
    const paper = document.getElementById("sauce-printer-paper-feed");
    if (!paper || paper.style.display === "none") {
        alert("출력할 라벨 데이터가 존재하지 않습니다.");
        return;
    }
    window.print();
}

function updateSauceUI() {
    const activeCount = sauceState.db.filter(item => item.Status !== "DISCARD").length;
    const activeCountEl = document.getElementById("sauce-active-count");
    if (activeCountEl) activeCountEl.innerText = `활성 소스: ${activeCount}개`;

    const gridContainer = document.getElementById("sauce-grid-container");
    if (gridContainer) {
        if (sauceState.db.length === 0) {
            gridContainer.innerHTML = `
                <div class="empty-grid-msg" style="text-align: center; padding: 40px; color: var(--text-muted);">
                    현재 관리 중인 피자소스가 없습니다.<br>
                    ID를 입력하거나 PREP (최초개봉) 버튼을 클릭하여 소스통을 추가하세요.
                </div>
            `;
        } else {
            let gridHtml = "";
            sauceState.db.forEach(item => {
                let currentRem = item.Rem_Valid_Min;
                if (item.Status === "PREP" || item.Status === "OUT") {
                    const lastAction = new Date(item.Last_Action_Time);
                    let elapsedMin = 0;
                    if (sauceState.systemTime > lastAction) {
                        elapsedMin = (sauceState.systemTime - lastAction) / (1000 * 60);
                    }
                    currentRem = Math.max(0, item.Total_Valid_Min - item.Accum_Used_Min - elapsedMin);
                }

                const pct = (currentRem / item.Total_Valid_Min) * 100;
                let progClass = "";
                if (pct < 15) progClass = "danger";
                else if (pct < 45) progClass = "warning";
                if (item.Status === "IN") progClass += " paused";

                const isSelected = (sauceState.selectedId === item.Source_ID) ? "selected" : "";
                let statusBadgeClass = `badge-sauce badge-${item.Status.toLowerCase()}`;
                let statusLabel = item.Status;

                gridHtml += `
                    <div class="sauce-card ${isSelected}" onclick="selectSauceCard('${item.Source_ID}')">
                        <div class="sauce-card-header">
                            <span class="sauce-id">${item.Source_ID}</span>
                            <span class="${statusBadgeClass}">${statusLabel}</span>
                        </div>
                        <div style="font-size: 0.8rem; display: flex; flex-direction: column; gap: 2px;">
                            <div style="display: flex; justify-content: space-between;">
                                <span style="color: var(--text-muted);">최종 시작:</span>
                                <span>${formatSauceDateTimeShort(new Date(item.Last_Action_Time))}</span>
                            </div>
                            <div style="display: flex; justify-content: space-between;">
                                <span style="color: var(--text-muted);">예상 폐기:</span>
                                <span style="color: ${item.Status === 'DISCARD' || currentRem <= 0 ? '#ef4444' : 'inherit'}; font-weight: 700;">${formatSauceDateTimeShort(item.Est_Discard_Time)}</span>
                            </div>
                        </div>
                        <div>
                            <div class="progress-container">
                                <div class="progress-bar ${progClass}" style="width: ${item.Status === 'DISCARD' ? 0 : pct}%;"></div>
                            </div>
                            <div style="display: flex; justify-content: space-between; font-size: 0.75rem; margin-top: 4px;">
                                <span style="color: var(--text-muted);">잔여시간:</span>
                                <span style="font-weight: 700;">${item.Status === 'IN' ? '차감 중지 (IN)' : (item.Status === 'DISCARD' ? '폐기 완료' : formatSauceDuration(currentRem))}</span>
                            </div>
                        </div>
                    </div>
                `;
            });
            gridContainer.innerHTML = gridHtml;
        }
    }

    const tableBody = document.getElementById("sauce-db-table-body");
    if (tableBody) {
        let tableHtml = "";
        sauceState.db.forEach(item => {
            let trClass = item._updated ? "updated" : "";
            delete item._updated;
            tableHtml += `
                <tr class="${trClass}">
                    <td style="font-weight: 700;">${item.Source_ID}</td>
                    <td><span class="badge-sauce badge-${item.Status.toLowerCase()}">${item.Status}</span></td>
                    <td>${item.Total_Valid_Min}</td>
                    <td>${Math.round(item.Accum_Used_Min)}</td>
                    <td>${Math.round(item.Rem_Valid_Min)}</td>
                    <td>${formatSauceDateTimeShort(new Date(item.Last_Action_Time))}</td>
                    <td>${formatSauceDateTimeShort(item.Est_Discard_Time)}</td>
                </tr>
            `;
        });
        tableBody.innerHTML = tableHtml;
    }
}

function selectSauceCard(id) {
    sauceState.selectedId = (sauceState.selectedId === id) ? null : id;
    const item = sauceState.db.find(i => i.Source_ID === id);
    if (item) renderSaucePrintedLabel(item);
    updateSauceUI();
}

// ==========================================
// Authentication Logic & Helpers
// ==========================================
async function checkAuthStatus() {
    try {
        const status = await apiGet('/api/auth/status');
        if (status.loggedIn) {
            state.user = status.user;
            if (loginOverlay) loginOverlay.style.display = "none";
            if (logoutBtn) logoutBtn.style.display = "flex";
            
            applyRoleRestrictions();
            await loadAllData();
            renderMainDataViews();
            
            if (state.ingredients.length > 0) {
                selectIngredient(state.ingredients[0].name);
            }
        } else {
            state.user = null;
            if (loginOverlay) loginOverlay.style.display = "flex";
            if (logoutBtn) logoutBtn.style.display = "none";
        }
    } catch (e) {
        console.error("Auth check failed:", e);
        if (loginOverlay) loginOverlay.style.display = "flex";
        if (logoutBtn) logoutBtn.style.display = "none";
    }
}

function applyRoleRestrictions() {
    const manageTabBtn = document.querySelector('.main-tab[data-tab="tab-manage"]');
    if (!state.user) return;
    
    if (state.user.role === 'admin') {
        if (settingsOpenBtn) settingsOpenBtn.style.display = "flex";
        if (manageTabBtn) manageTabBtn.style.display = "flex";
    } else {
        // Staff role restrictions
        if (settingsOpenBtn) settingsOpenBtn.style.display = "none";
        if (manageTabBtn) manageTabBtn.style.display = "none";
        
        // Force to Print Tab
        state.activeTab = "tab-print";
        document.querySelectorAll(".main-tab").forEach(t => {
            if (t.dataset.tab === "tab-print") t.classList.add("active");
            else t.classList.remove("active");
        });
        document.querySelectorAll(".tab-content").forEach(c => {
            if (c.id === "tab-print") c.classList.add("active");
            else c.classList.remove("active");
        });
    }
}

async function handleLogin(e) {
    e.preventDefault();
    if (loginErrorMsg) loginErrorMsg.style.display = "none";
    
    const username = loginUsernameInput ? loginUsernameInput.value.trim() : "";
    const password = loginPasswordInput ? loginPasswordInput.value : "";
    
    if (!username || !password) {
        showLoginError("아이디와 비밀번호를 모두 입력해 주세요.");
        return;
    }
    
    try {
        const response = await apiPost('/api/auth/login', { username, password });
        if (response.success) {
            state.user = response.user;
            if (loginUsernameInput) loginUsernameInput.value = "";
            if (loginPasswordInput) loginPasswordInput.value = "";
            if (loginOverlay) loginOverlay.style.display = "none";
            if (logoutBtn) logoutBtn.style.display = "flex";
            
            applyRoleRestrictions();
            await loadAllData();
            renderMainDataViews();
            
            if (state.ingredients.length > 0) {
                selectIngredient(state.ingredients[0].name);
            }
            if (window.lucide) window.lucide.createIcons();
        }
    } catch (err) {
        if (err.ipBlocked || (err.message && err.message.includes('허용되지 않은 IP'))) {
            showAccessDeniedModal(err.message, err.clientIp);
        } else {
            showLoginError(err.message || "로그인 요청에 실패했습니다.");
        }
    }
}

function showLoginError(msg) {
    if (loginErrorMsg) {
        loginErrorMsg.textContent = msg;
        loginErrorMsg.style.display = "block";
    }
}

async function handleLogout() {
    if (!confirm("로그아웃 하시겠습니까?")) return;
    try {
        await apiPost('/api/auth/logout', {});
        state.user = null;
        if (loginOverlay) loginOverlay.style.display = "flex";
        if (logoutBtn) logoutBtn.style.display = "none";
        
        // Reset state
        state.ingredients = [];
        state.categories = [];
        state.locations = [];
        state.selectedId = null;
        state.selectedStorage = null;
        
        if (ingredientsGrid) ingredientsGrid.innerHTML = "";
        if (selectedIngDisplay) selectedIngDisplay.textContent = "재료를 선택해 주세요";
        if (storageOptionsContainer) storageOptionsContainer.innerHTML = "";
    } catch (e) {
        console.error("Logout failed:", e);
        state.user = null;
        if (loginOverlay) loginOverlay.style.display = "flex";
        if (logoutBtn) logoutBtn.style.display = "none";
    }
}
