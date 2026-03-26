// LibreWolf user.js - Neovim-like setup
// Enable userChrome.css customization
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Dark theme
user_pref("browser.theme.content-theme", 0); // 0 = dark
user_pref("browser.theme.toolbar-theme", 0);
user_pref("ui.systemUsesDarkTheme", 1);
user_pref("browser.in-content.dark-mode", true);

// Enable SVG context-properties for TST icons
user_pref("svg.context-properties.content.enabled", true);

// Compact UI density
user_pref("browser.compactmode.show", true);
user_pref("browser.uidensity", 1); // 1 = compact

// Smooth scrolling (vim-like feel)
user_pref("general.smoothScroll", true);
user_pref("general.smoothScroll.msdPhysics.enabled", true);
user_pref("general.smoothScroll.currentVelocityWeighting", 0);
user_pref("general.smoothScroll.stopDecelerationWeighting", 0.82);

// Disable annoying UI elements
user_pref("browser.tabs.tabmanager.enabled", false);
user_pref("browser.urlbar.suggest.topsites", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");

// Minimal new tab
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);

// Open blank page on new tab
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.homepage", "about:blank");

// Sidebar (for Tree Style Tab)
user_pref("sidebar.verticalTabs", false); // we use TST, not native vertical tabs

// ===== Font Configuration =====
// Arabic fonts
user_pref("font.name.serif.ar", "Noto Naskh Arabic");
user_pref("font.name.sans-serif.ar", "Noto Sans Arabic");
user_pref("font.name.monospace.ar", "Noto Sans Arabic");
user_pref("font.size.variable.ar", 18);

// French fonts
user_pref("font.name.serif.x-western", "Noto Serif");
user_pref("font.name.sans-serif.x-western", "Inter");
user_pref("font.name.monospace.x-western", "JetBrainsMono Nerd Font");
user_pref("font.size.variable.x-western", 15);

// Default fonts
user_pref("font.default.ar", "sans-serif");
user_pref("font.default.x-western", "sans-serif");

// ===== Reader Mode settings =====
user_pref("reader.color_scheme", "dark");
user_pref("reader.content_width", 5);
user_pref("reader.font_size", 6);
user_pref("reader.font_type", "sans-serif");
