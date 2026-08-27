/* Accessibility fix on top of the Material theme defaults.
   Finding from the axe-core 4.13.0 audit (2026-08-27, issue #86):
   the theme's search overlay is a role="dialog" element without an
   accessible name (WCAG 4.1.2). The search UI is JavaScript-only, so
   naming it from JavaScript covers every state in which the dialog is
   operable. Label text matches the theme's own German search
   placeholder. */
document.addEventListener("DOMContentLoaded", function () {
  var search = document.querySelector('.md-search[role="dialog"]');
  if (search && !search.hasAttribute("aria-label")) {
    search.setAttribute("aria-label", "Suche");
  }
});
