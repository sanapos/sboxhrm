// Auto-apply translations on page load
document.addEventListener('DOMContentLoaded', () => {
    // Map of selectors to translation keys
    const translationMap = {
        // Hero Section
        '.hero .badge': 'hero_badge',
        '.hero-title': null, // Special handling for split text
        '.hero-description': 'hero_description',
        '.hero-cta .btn-primary': 'hero_cta_trial',
        '.hero-cta .btn-secondary': 'hero_cta_demo',

        // Stats
        '.stat-item:nth-child(1) .stat-label': 'hero_stat_1_label',
        '.stat-item:nth-child(2) .stat-label': 'hero_stat_2_label',
        '.stat-item:nth-child(3) .stat-label': 'hero_stat_3_label',

        // Dashboard Mockup
        '.mockup-title': 'dashboard_title',
        '.metric-card:nth-child(1) .metric-label': 'metric_employees',
        '.metric-card:nth-child(1) .metric-change': 'metric_employees_change',
        '.metric-card:nth-child(2) .metric-label': 'metric_attendance',
        '.metric-card:nth-child(2) .metric-change': 'metric_attendance_change',

        // Features Section
        '.features .badge': 'features_badge',
        '.features .section-title': 'features_title',
        '.features .section-description': 'features_description',

        // Feature Cards
        '.feature-card:nth-child(1) .feature-title': 'feature_1_title',
        '.feature-card:nth-child(1) .feature-description': 'feature_1_desc',
        '.feature-card:nth-child(1) .feature-list li:nth-child(1)': 'feature_1_item_1',
        '.feature-card:nth-child(1) .feature-list li:nth-child(2)': 'feature_1_item_2',
        '.feature-card:nth-child(1) .feature-list li:nth-child(3)': 'feature_1_item_3',

        '.feature-card:nth-child(2) .feature-title': 'feature_2_title',
        '.feature-card:nth-child(2) .feature-description': 'feature_2_desc',
        '.feature-card:nth-child(2) .feature-list li:nth-child(1)': 'feature_2_item_1',
        '.feature-card:nth-child(2) .feature-list li:nth-child(2)': 'feature_2_item_2',
        '.feature-card:nth-child(2) .feature-list li:nth-child(3)': 'feature_2_item_3',

        '.feature-card:nth-child(3) .feature-title': 'feature_3_title',
        '.feature-card:nth-child(3) .feature-description': 'feature_3_desc',
        '.feature-card:nth-child(3) .feature-list li:nth-child(1)': 'feature_3_item_1',
        '.feature-card:nth-child(3) .feature-list li:nth-child(2)': 'feature_3_item_2',
        '.feature-card:nth-child(3) .feature-list li:nth-child(3)': 'feature_3_item_3',

        '.feature-card:nth-child(4) .feature-title': 'feature_4_title',
        '.feature-card:nth-child(4) .feature-description': 'feature_4_desc',
        '.feature-card:nth-child(4) .feature-list li:nth-child(1)': 'feature_4_item_1',
        '.feature-card:nth-child(4) .feature-list li:nth-child(2)': 'feature_4_item_2',
        '.feature-card:nth-child(4) .feature-list li:nth-child(3)': 'feature_4_item_3',

        '.feature-card:nth-child(5) .feature-title': 'feature_5_title',
        '.feature-card:nth-child(5) .feature-description': 'feature_5_desc',
        '.feature-card:nth-child(5) .feature-list li:nth-child(1)': 'feature_5_item_1',
        '.feature-card:nth-child(5) .feature-list li:nth-child(2)': 'feature_5_item_2',
        '.feature-card:nth-child(5) .feature-list li:nth-child(3)': 'feature_5_item_3',

        '.feature-card:nth-child(6) .feature-title': 'feature_6_title',
        '.feature-card:nth-child(6) .feature-description': 'feature_6_desc',
        '.feature-card:nth-child(6) .feature-list li:nth-child(1)': 'feature_6_item_1',
        '.feature-card:nth-child(6) .feature-list li:nth-child(2)': 'feature_6_item_2',
        '.feature-card:nth-child(6) .feature-list li:nth-child(3)': 'feature_6_item_3',

        // How It Works
        '.how-it-works .badge': 'how_badge',
        '.how-it-works .section-title': 'how_title',
        '.how-it-works .section-description': 'how_description',

        '.step:nth-child(1) .step-title': 'step_1_title',
        '.step:nth-child(1) .step-description': 'step_1_desc',
        '.step:nth-child(2) .step-title': 'step_2_title',
        '.step:nth-child(2) .step-description': 'step_2_desc',
        '.step:nth-child(3) .step-title': 'step_3_title',
        '.step:nth-child(3) .step-description': 'step_3_desc',

        // Benefits
        '.benefits .badge': 'benefits_badge',
        '.benefits .section-title': 'benefits_title',
        '.benefits .section-description': 'benefits_description',

        '.benefit-item:nth-child(1) h4': 'benefit_1_title',
        '.benefit-item:nth-child(1) p': 'benefit_1_desc',
        '.benefit-item:nth-child(2) h4': 'benefit_2_title',
        '.benefit-item:nth-child(2) p': 'benefit_2_desc',
        '.benefit-item:nth-child(3) h4': 'benefit_3_title',
        '.benefit-item:nth-child(3) p': 'benefit_3_desc',
        '.benefit-item:nth-child(4) h4': 'benefit_4_title',
        '.benefit-item:nth-child(4) p': 'benefit_4_desc',

        // Floating Cards
        '.card-1 .card-header span': 'card_status_title',
        '.card-1 .card-value': 'card_status_value',
        '.card-1 .card-subtext': 'card_status_desc',

        '.card-2 .card-header span': 'card_performance_title',
        '.card-2 .card-value': 'card_performance_value',
        '.card-2 .card-subtext': 'card_performance_desc',

        '.card-3 .card-header span': 'card_security_title',
        '.card-3 .card-value': 'card_security_value',
        '.card-3 .card-subtext': 'card_security_desc',

        // CTA
        '.cta-title': 'cta_title',
        '.cta-description': 'cta_description',
        '.cta-buttons .btn-primary': 'cta_btn_trial',
        '.cta-buttons .btn-secondary': 'cta_btn_demo',
        '.cta-note': 'cta_note',

        // Footer
        '.footer-description': 'footer_description',
        '.footer-column:nth-child(1) h4': 'footer_product',
        '.footer-column:nth-child(2) h4': 'footer_company',
        '.footer-column:nth-child(3) h4': 'footer_support',
    };

    // Apply data-i18n attributes
    Object.entries(translationMap).forEach(([selector, key]) => {
        if (key) {
            const element = document.querySelector(selector);
            if (element) {
                element.setAttribute('data-i18n', key);
            }
        }
    });

    // Special handling for hero title (split text)
    const heroTitle = document.querySelector('.hero-title');
    if (heroTitle) {
        const updateHeroTitle = () => {
            const t = translations[currentLanguage];
            heroTitle.innerHTML = `
                ${t.hero_title_1}
                <span class="gradient-text">${t.hero_title_2}</span>
            `;
        };
        // Store the update function for later use
        window.updateHeroTitle = updateHeroTitle;
    }

    // Initialize with current language
    updateContent();
    if (window.updateHeroTitle) window.updateHeroTitle();
});

// Override the original updateContent to include hero title
const originalUpdateContent = updateContent;
updateContent = function () {
    originalUpdateContent();
    if (window.updateHeroTitle) window.updateHeroTitle();
};
