# Multi-Language Support - ZKTecoADMS Landing Page

## 🌍 Languages Supported

- **English (EN)** 🇺🇸
- **Vietnamese (VI)** 🇻🇳

## ✨ Features

### Language Switcher
- **Location**: Top navigation bar (next to "Get Started" button)
- **Design**: Clean dropdown menu with flag icons
- **Persistence**: Selected language saved in localStorage
- **Smooth Transitions**: Animated dropdown with fade-in effect

### How It Works

1. **Click the language button** (shows "EN" or "VI")
2. **Select your preferred language** from the dropdown:
   - 🇺🇸 English
   - 🇻🇳 Tiếng Việt
3. **Page content updates instantly** - no reload required
4. **Language preference is saved** - remembered on next visit

## 📝 Translation Coverage

All sections are fully translated:

### Navigation
- Features / Tính Năng
- How It Works / Cách Hoạt Động
- Benefits / Lợi Ích
- Pricing / Bảng Giá
- Get Started / Bắt Đầu

### Hero Section
- Badge, Title, Description
- CTA Buttons
- Statistics (Employees Managed, HR Tasks Automated, Saved Per Month)

### Features Section (6 Features)
1. Automated Time & Attendance / Chấm Công Tự Động
2. Workforce Scheduling / Lập Lịch Lực Lượng Lao Động
3. Leave & PTO Tracking / Theo Dõi Nghỉ Phép & PTO
4. HR Analytics & Insights / Phân Tích & Thông Tin HR
5. Employee Data Management / Quản Lý Dữ Liệu Nhân Viên
6. Data Security & Compliance / Bảo Mật & Tuân Thủ Dữ Liệu

### How It Works (3 Steps)
1. Connect Your Devices / Kết Nối Thiết Bị
2. Onboard Your Employees / Tuyển Dụng Nhân Viên
3. Optimize & Grow / Tối Ưu & Phát Triển

### Benefits Section
- 4 key benefits fully translated
- Floating cards (System Status, Performance, Security)

### CTA Section
- Title, Description, Buttons, Note

### Footer
- All links and sections translated

## 🔧 Technical Implementation

### Files Added/Modified

1. **translations.js** (NEW)
   - Complete translation dictionary
   - Language switching logic
   - localStorage persistence

2. **index.html** (MODIFIED)
   - Added language switcher UI
   - Added `data-i18n` attributes to all translatable elements
   - Included translations.js script

3. **styles.css** (MODIFIED)
   - Language switcher button styles
   - Dropdown menu animations
   - Hover effects and transitions

4. **script.js** (MODIFIED)
   - Toggle menu function
   - Click outside to close functionality

### How to Add New Translations

To add more content translations:

1. Open `translations.js`
2. Add new key-value pairs to both `en` and `vi` objects:
   ```javascript
   en: {
       new_key: "English text",
       // ...
   },
   vi: {
       new_key: "Vietnamese text",
       // ...
   }
   ```
3. Add `data-i18n="new_key"` attribute to HTML element

### How to Add New Languages

To add a new language (e.g., French):

1. Add translation object in `translations.js`:
   ```javascript
   fr: {
       nav_features: "Fonctionnalités",
       // ... all translations
   }
   ```

2. Add language option in HTML:
   ```html
   <button onclick="setLanguage('fr')" class="language-option">
       <span class="flag">🇫🇷</span> Français
   </button>
   ```

## 🎨 Design Details

### Language Button
- Clean, minimal design
- Border changes color on hover
- Shows current language code (EN/VI)

### Dropdown Menu
- Smooth fade-in animation
- Shadow for depth
- Flag emojis for visual recognition
- Hover effect on options

### User Experience
- Instant content update (no page reload)
- Smooth transitions
- Persistent selection across sessions
- Accessible keyboard navigation

## 📱 Responsive Behavior

- **Desktop**: Dropdown menu on right side
- **Mobile**: Same functionality, optimized for touch
- **All devices**: Language preference persists

## 🚀 Usage

The language switcher is **live and functional**. Users can:

1. Click the language button in the navigation
2. Select their preferred language
3. See all content update immediately
4. Return later and see their language preference remembered

## 🔍 Testing

To test the language switcher:

1. Visit `http://localhost:8000`
2. Click the "EN" button in the navigation
3. Select "🇻🇳 Tiếng Việt"
4. Watch all content change to Vietnamese
5. Refresh the page - Vietnamese is still selected
6. Switch back to English anytime

## 💡 Benefits

✅ **Better User Experience** - Users can read in their native language  
✅ **Wider Audience** - Reach Vietnamese-speaking companies  
✅ **Professional** - Shows attention to localization  
✅ **Persistent** - Remembers user preference  
✅ **Fast** - No page reload required  
✅ **Extensible** - Easy to add more languages  

---

**Implementation Complete!** 🎉

The landing page now supports both English and Vietnamese with a beautiful, functional language switcher.
