/* Dual-domain SEO: sboxpos.com = POS, sboxhrm.com = HRM. ?site=pos|hrm on localhost. */
(function (global) {
  function detectSite() {
    try {
      var q = new URLSearchParams(location.search).get('site');
      if (q === 'pos' || q === 'hrm') return q;
    } catch (e) {}
    var h = (location.hostname || '').toLowerCase();
    if (h === 'sboxpos.com' || h === 'www.sboxpos.com' || h.indexOf('sboxpos.') === 0) return 'pos';
    return 'hrm';
  }

  function originFor(site) {
    if (location.origin && location.origin.indexOf('http') === 0) return location.origin;
    return site === 'pos' ? 'https://sboxpos.com' : 'https://sboxhrm.com';
  }

  function homeSeo(site) {
    var isPos = site === 'pos';
    var origin = originFor(site);
    if (isPos) {
      return {
        site: site,
        origin: origin,
        brand: 'SBOX POS',
        title: 'Phần mềm POS bán hàng, quản lý cửa hàng & kho | SBOX POS',
        description: 'Phần mềm POS bán hàng SBOX: bán tại quầy, sơ đồ bàn, in hóa đơn nhiệt và phiếu bếp, quản lý kho, báo cáo doanh thu realtime. POS đa ngành — dùng thử miễn phí trên web và máy POS Android.',
        keywords: 'phần mềm POS, phần mềm bán hàng, POS đa ngành, POS F&B, POS nhà hàng, POS cà phê, POS bán lẻ, quản lý cửa hàng, sơ đồ bàn, in hóa đơn nhiệt, phiếu bếp, quản lý kho, báo cáo doanh thu, SBOX POS, máy POS Android',
        ogImage: origin + '/images/landing/pos/sbox-pos-og.jpg?v=3',
        ogImageAlt: 'SBOX POS – phần mềm bán hàng trên máy POS, tablet và web',
        themeColor: '#2E7D32'
      };
    }
    return {
      site: site,
      origin: origin,
      brand: 'SBOX HRM',
      title: 'Phần mềm chấm công & tính lương ZKTeco | SBOX HRM',
      description: 'Phần mềm chấm công khuôn mặt AI, kết nối máy ZKTeco ADMS, quản lý ca và bảng lương tự động cho doanh nghiệp Việt Nam. Dùng thử miễn phí trên web & Android — SBOX HRM.',
      keywords: 'phần mềm chấm công, phần mềm tính lương, chấm công khuôn mặt, chấm công ZKTeco, phần mềm bảng lương, quản lý ca làm việc, phần mềm quản lý nhân sự, HRM Việt Nam, SBOX HRM, ADMS',
      ogImage: origin + '/images/landing/screenshot-01.jpg',
      ogImageAlt: 'Giao diện SBOX HRM – phần mềm quản lý nhân sự và chấm công',
      themeColor: '#0C56D0'
    };
  }

  function appSeo(site) {
    var base = homeSeo(site);
    if (site === 'pos') {
      base.title = 'SBOX POS – Phần mềm bán hàng & quản lý cửa hàng';
      base.description = 'Đăng nhập SBOX POS — bán hàng tại quầy, sơ đồ bàn, in hóa đơn/phiếu bếp, quản lý kho và báo cáo doanh thu trên web, máy POS Android và tablet.';
    } else {
      base.title = 'SBOX HRM – Phần mềm quản lý nhân sự, chấm công & bảng lương';
      base.description = 'SBOX HRM – Phần mềm quản lý nhân sự cho doanh nghiệp Việt Nam: chấm công khuôn mặt, ZKTeco, ca làm, bảng lương tự động, báo cáo realtime. Dùng thử miễn phí trên web và Android.';
    }
    return base;
  }

  function esc(s) {
    return String(s || '')
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;');
  }

  function setEl(id, attr, value) {
    var el = document.getElementById(id);
    if (!el || value == null || value === '') return;
    if (attr === 'text') el.textContent = value;
    else el.setAttribute(attr, value);
  }

  function applyExisting(cfg, opts) {
    opts = opts || {};
    var robots = opts.robots || 'index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1';
    document.title = cfg.title;
    setEl('seo-title', 'text', cfg.title);
    setEl('seo-description', 'content', cfg.description);
    setEl('seo-keywords', 'content', cfg.keywords);
    var author = document.querySelector('meta[name="author"]');
    if (author) author.setAttribute('content', cfg.brand);
    var robotsEl = document.querySelector('meta[name="robots"]');
    if (robotsEl) robotsEl.setAttribute('content', robots);
    setEl('seo-canonical', 'href', cfg.origin + '/');
    setEl('seo-og-site', 'content', cfg.brand);
    setEl('seo-og-url', 'content', cfg.origin + '/');
    setEl('seo-og-title', 'content', cfg.title);
    setEl('seo-og-description', 'content', cfg.description);
    setEl('seo-og-image', 'content', cfg.ogImage);
    var ogType = document.getElementById('seo-og-image-type');
    if (!ogType) {
      var img = document.getElementById('seo-og-image');
      if (img) img.setAttribute('content', cfg.ogImage);
    }
    setEl('seo-og-image-alt', 'content', cfg.ogImageAlt);
    setEl('seo-tw-title', 'content', cfg.title);
    setEl('seo-tw-description', 'content', cfg.description);
    setEl('seo-tw-image', 'content', cfg.ogImage);
    document.querySelectorAll('link[hreflang]').forEach(function (l) {
      l.setAttribute('href', cfg.origin + '/');
    });
    var theme = document.querySelector('meta[name="theme-color"]');
    if (theme && cfg.themeColor) theme.setAttribute('content', cfg.themeColor);
    if (opts.manifest) {
      var man = document.querySelector('link[rel="manifest"]');
      if (man) man.setAttribute('href', opts.manifest);
    }
    if (opts.appleTitle) {
      var apple = document.querySelector('meta[name="apple-mobile-web-app-title"]');
      if (apple) apple.setAttribute('content', cfg.brand);
    }
  }

  function writeHeadTags(cfg, opts) {
    if (document.getElementById('seo-title')) {
      applyExisting(cfg, opts);
      return;
    }
    opts = opts || {};
    var robots = opts.robots || 'index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1';
    var o = esc(cfg.origin);
    var parts = [
      '<title id="seo-title">' + esc(cfg.title) + '</title>',
      '<meta id="seo-description" name="description" content="' + esc(cfg.description) + '">',
      '<meta id="seo-keywords" name="keywords" content="' + esc(cfg.keywords) + '">',
      '<meta name="author" content="' + esc(cfg.brand) + '">',
      '<meta name="robots" content="' + esc(robots) + '">',
      '<meta id="seo-google-verification" name="google-site-verification" content="" data-optional="1">',
      '<link id="seo-canonical" rel="canonical" href="' + o + '/">',
      '<link rel="alternate" hreflang="vi" href="' + o + '/">',
      '<link rel="alternate" hreflang="x-default" href="' + o + '/">',
      '<meta property="og:type" content="website">',
      '<meta id="seo-og-site" property="og:site_name" content="' + esc(cfg.brand) + '">',
      '<meta property="og:locale" content="vi_VN">',
      '<meta id="seo-og-url" property="og:url" content="' + o + '/">',
      '<meta id="seo-og-title" property="og:title" content="' + esc(cfg.title) + '">',
      '<meta id="seo-og-description" property="og:description" content="' + esc(cfg.description) + '">',
      '<meta id="seo-og-image" property="og:image" content="' + esc(cfg.ogImage) + '">',
      '<meta property="og:image:width" content="1200">',
      '<meta property="og:image:height" content="630">',
      '<meta id="seo-og-image-alt" property="og:image:alt" content="' + esc(cfg.ogImageAlt) + '">',
      '<meta name="twitter:card" content="summary_large_image">',
      '<meta id="seo-tw-title" name="twitter:title" content="' + esc(cfg.title) + '">',
      '<meta id="seo-tw-description" name="twitter:description" content="' + esc(cfg.description) + '">',
      '<meta id="seo-tw-image" name="twitter:image" content="' + esc(cfg.ogImage) + '">'
    ];
    if (opts.themeColor !== false) {
      parts.push('<meta name="theme-color" content="' + esc(cfg.themeColor) + '">');
    }
    if (opts.manifest) {
      parts.push('<link rel="manifest" href="' + esc(opts.manifest) + '">');
    }
    if (opts.appleTitle) {
      parts.push('<meta name="apple-mobile-web-app-title" content="' + esc(cfg.brand) + '">');
    }
    document.write(parts.join('\n'));
  }

  global.SboxSiteSeo = {
    detectSite: detectSite,
    homeSeo: homeSeo,
    appSeo: appSeo,
    writeHeadTags: writeHeadTags,
    esc: esc
  };
})(window);
