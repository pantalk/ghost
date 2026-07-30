/*
 * Pantalk mascot - the ghost figure overlaid on the KasmVNC client page.
 *
 * Mounts the Pantalk logo into the lower-left corner of the client page, above
 * the noVNC canvas but outside the remote framebuffer.  Styling lives in
 * mascot.css; the artwork is the same geometry as site/components/Logo.jsx.
 *
 * Because the overlay is positioned against the page rather than the desktop,
 * it is unaffected by the display resize KasmVNC performs when a client
 * connects - the resize that openbox/autostart's wallpaper watcher exists to
 * paper over.
 *
 * Clicking the ghost opens the selected harness.  Rather than reaching into
 * noVNC, it synthesises the same keystroke a keyboard user would press and
 * lets noVNC's own keyboard pipeline translate and transmit it; Openbox has
 * that key bound to desktop-harness by the desktop base.  The RFB object is
 * module-private in the bundled client and is deliberately not touched.
 */

;(function () {
  'use strict'

  var MARKUP = [
    '<div class="pantalk_mascot_glow"></div>',
    '<svg class="pantalk_mascot_logo" viewBox="0 0 512 512" fill="none"',
    ' xmlns="http://www.w3.org/2000/svg">',
    // Body: dome top, signal-wave bottom.
    '<path d="M115.199 384V204.8C115.199 127.04 178.239 64 255.999 64C333.759',
    ' 64 396.799 127.04 396.799 204.8V384C375.466 358.4 354.133 358.4 332.799',
    ' 384C311.466 409.6 290.133 409.6 268.799 384C247.466 358.4 226.133 358.4',
    ' 204.799 384C183.466 409.6 162.133 409.6 140.799 384C132.266 375.467',
    ' 123.733 375.467 115.199 384Z" fill="currentColor" fill-opacity="0.15"',
    ' stroke="currentColor" stroke-width="19.2" stroke-linecap="round"',
    ' stroke-linejoin="round"/>',
    // Headphone band.
    '<path d="M115.199 217.6C115.199 140.8 162.133 102.4 255.999 102.4C349.866',
    ' 102.4 396.799 140.8 396.799 217.6" stroke="currentColor"',
    ' stroke-width="19.2" stroke-linecap="round" fill="none" opacity="0.4"/>',
    // Left earpiece.
    '<path d="M115.5 210C115.5 192.327 113.673 192 96 192C78.3269 192 64',
    ' 206.327 64 224V262.4C64 280.073 78.3269 294.4 96 294.4C113.673 294.4',
    ' 115.5 298.673 115.5 281V210Z" fill="currentColor" fill-opacity="0.3"',
    ' stroke="currentColor" stroke-width="15.36"/>',
    // Right earpiece.
    '<path d="M397 210C397 192.327 398.827 192 416.5 192C434.173 192 448.5',
    ' 206.327 448.5 224V262.4C448.5 280.073 434.173 294.4 416.5 294.4C398.827',
    ' 294.4 397 298.673 397 281V210Z" fill="currentColor" fill-opacity="0.3"',
    ' stroke="currentColor" stroke-width="15.36"/>',
    // Eyes.
    '<circle cx="204.799" cy="204.8" r="25.6" fill="currentColor"/>',
    '<circle cx="307.202" cy="204.8" r="25.6" fill="currentColor"/>',
    // Smile.
    '<path d="M204.801 281.6C238.934 311.466 273.067 311.466 307.201 281.6"',
    ' stroke="currentColor" stroke-width="19.2" stroke-linecap="round"',
    ' fill="none"/>',
    '</svg>',
  ].join('')

  function init() {
    if (document.getElementById('pantalk_mascot')) {
      return
    }

    var root = document.createElement('div')
    root.id = 'pantalk_mascot'
    root.setAttribute('aria-hidden', 'true')
    root.innerHTML = MARKUP
    document.body.appendChild(root)

    // Fade in on the next frame so the transition has a starting value.
    requestAnimationFrame(function () {
      root.classList.add('is-ready')
    })

    root.addEventListener('click', function (event) {
      event.preventDefault()
      sendShortcut()
    })
  }

  // noVNC binds its keydown/keyup handlers to the canvas it creates inside
  // #noVNC_container, so that is where the events have to land.  The other
  // ids are fallbacks in case a future client build moves things.
  function keyboardTarget() {
    return (
      document.querySelector('#noVNC_container canvas') ||
      document.getElementById('noVNC_container') ||
      document.getElementById('noVNC_keyboardinput')
    )
  }

  function key(target, type, code, keyName, ctrl, shift) {
    target.dispatchEvent(
      new KeyboardEvent(type, {
        code: code,
        key: keyName,
        ctrlKey: ctrl,
        shiftKey: shift,
        bubbles: true,
        cancelable: true,
      })
    )
  }

  // Ctrl+Shift+G, matching the Openbox binding in openbox/rc.xml.
  //
  // Only Control and Shift are used, because they are the only modifiers that
  // survive this path unchanged on every client OS. noVNC normalises Mac
  // keyboards to behave like Linux ones and rewrites the keysym before it
  // reaches the server:
  //
  //     if (isMac() || isIOS()) switch (keysym) {
  //       case XK_Super_L: keysym = XK_Alt_L;             break
  //       case XK_Alt_L:   keysym = XK_Mode_switch;       break
  //       case XK_Alt_R:   keysym = XK_ISO_Level3_Shift;  break
  //     }
  //
  // So Alt from a Mac client arrives as an AltGr-class modifier on Mod5, not
  // Alt on Mod1, and an Openbox binding written as C-A-g never matches - the
  // key falls through to whatever application has focus instead. Super is
  // shuffled too. Control and Shift appear nowhere in that table, so the same
  // synthetic events produce the same X keysyms from any client.
  //
  // Lowercase 'g' with Shift held, not 'G': asking for the uppercase keysym
  // makes Xvnc synthesise a CapsLock press to reach it, and press-plus-release
  // of CapsLock toggles the lock state on every click.
  //
  // Two further constraints, learned the same way: KasmVNC's translateShortcuts
  // rewrites Cmd+key into Ctrl+key on macOS and strands Control down, so Meta
  // is unusable; and a dedicated key like F13 is not in this desktop's keymap,
  // so Openbox cannot passively grab it and the press vanishes silently.
  //
  // The modifier releases are in a finally block: modifiers that go down and
  // never come back up leave every later keystroke on the desktop behaving as
  // a shortcut.
  function sendShortcut() {
    var target = keyboardTarget()

    if (!target) {
      return
    }

    try {
      key(target, 'keydown', 'ControlLeft', 'Control', true, false)
      key(target, 'keydown', 'ShiftLeft', 'Shift', true, true)
      key(target, 'keydown', 'KeyG', 'g', true, true)
      key(target, 'keyup', 'KeyG', 'g', true, true)
    } finally {
      key(target, 'keyup', 'ShiftLeft', 'Shift', true, false)
      key(target, 'keyup', 'ControlLeft', 'Control', false, false)
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init)
  } else {
    init()
  }
})()
