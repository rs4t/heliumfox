// HeliumFox - settings the theme needs. Copy this file into your Firefox
// profile folder (next to the chrome folder). Firefox applies it on every start.

// Load chrome/userChrome.css and chrome/userContent.css
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Tabs and window buttons drawn in the title bar, like Helium
user_pref("browser.tabs.inTitlebar", 1);

// Helium is opaque: no see-through window (undo Latin Accent Plus' settings)
user_pref("browser.tabs.allow_transparent_browser", false);
user_pref("widget.windows.mica", false);
user_pref("gfx.webrender.all", true);

// Thin Windows 11 overlay scrollbars that only appear while scrolling
// (Helium turns on Chromium's fluent overlay scrollbars the same way)
user_pref("widget.non-native-theme.scrollbar.style", 5);
user_pref("widget.windows.overlay-scrollbars.enabled", true);
user_pref("widget.non-native-theme.win11.scrollbar.force-overlay-style", true);
