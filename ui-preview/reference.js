const state = { power: true, temperature: 23, mode: 'cold', fan: 'auto', sleep: false, airflow: 'vertical', light: true };
const modes = { cold: 'Frío', auto: 'Automático', wet: 'Deshumidificar', wind: 'Solo ventilador' };
const modeIcons = { cold: '#snowflake', auto: '#mode-auto-icon', wet: '#mode-dry-icon', wind: '#fan-icon' };
const fans = { auto: 'Auto', mute: 'Silencioso', low: 'Bajo', middle: 'Medio', high: 'Alto', strong: 'Turbo' };
const fanOrder = Object.keys(fans);
const byId = id => document.getElementById(id);
const panel = document.querySelector('.panel');
const controls = [...document.querySelectorAll('.control')];
const controlsScreen = byId('controls-screen');
const settingsScreen = byId('settings-screen');
const scene = byId('ac-scene');
const canvas = byId('air-canvas');
const context = canvas.getContext('2d');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const modeControl = byId('mode-control');
const modeButton = byId('mode');
const modeOptions = byId('mode-options');
const modeButtons = [...document.querySelectorAll('.mode-option')];
const fanControl = byId('fan-control');
const fanButton = byId('fan');
const fanPopover = byId('fan-popover');
const fanSlider = byId('fan-slider');
const fanKnob = byId('fan-knob');
let busy = false;
let showingSettings = false;
let animationFrame = 0;
let flowStarted = 0;
let windWidth = 340;
let fanHop;

function resizePreview() {
  const width = panel.offsetWidth;
  const height = panel.offsetHeight;
  const edge = ['top', 'bottom', 'left', 'right'].includes(panel.dataset.trayEdge) ? panel.dataset.trayEdge : 'bottom';
  panel.dataset.trayEdge = edge;
  const horizontal = edge === 'top' || edge === 'bottom';
  const span = horizontal ? width : height;
  const depth = (horizontal ? height : width) + 16;
  const fraction = Number(panel.dataset.trayAnchor ?? .5);
  const anchor = Math.max(44, Math.min(span - 44, span * (Number.isFinite(fraction) ? fraction : .5)));
  const outline = byId('panel-outline');
  byId('panel-frame').setAttribute('viewBox', horizontal ? `0 0 ${span} ${depth}` : `0 0 ${depth} ${span}`);
  outline.setAttribute('transform', ({
    top: 'matrix(1 0 0 1 0 0)', bottom: `matrix(1 0 0 -1 0 ${depth})`,
    left: 'matrix(0 1 1 0 0 0)', right: `matrix(0 1 -1 0 ${depth} 0)`,
  })[edge]);
  outline.setAttribute('d', `M27 17H${anchor - 16}
    C${anchor - 10} 17 ${anchor - 7} 1 ${anchor} 1
    C${anchor + 7} 1 ${anchor + 10} 17 ${anchor + 16} 17H${span - 27}
    Q${span - 1} 17 ${span - 1} 43V${depth - 27}
    Q${span - 1} ${depth - 1} ${span - 27} ${depth - 1}H27
    Q1 ${depth - 1} 1 ${depth - 27}V43Q1 17 27 17Z`);
  windWidth = scene.clientWidth;
  const scale = Math.min(Math.max(devicePixelRatio || 1, 2), 3);
  canvas.width = Math.round(windWidth * scale);
  canvas.height = Math.round(132 * scale);
  if (context) {
    context.setTransform(scale, 0, 0, scale, 0, 0);
    context.lineCap = 'round';
    context.lineJoin = 'round';
  }
  updateAnimation();
}

function pointToTray(icon, bounds = panel.getBoundingClientRect()) {
  const x = (icon.left + icon.right) / 2;
  const y = (icon.top + icon.bottom) / 2;
  const edge = y <= bounds.top ? 'top' : y >= bounds.bottom ? 'bottom' : x <= bounds.left ? 'left' : 'right';
  const horizontal = edge === 'top' || edge === 'bottom';
  panel.dataset.trayEdge = edge;
  panel.dataset.trayAnchor = String(horizontal ? (x - bounds.left) / bounds.width : (y - bounds.top) / bounds.height);
  resizePreview();
}

function drawWind(time) {
  if (!context) return;
  context.clearRect(0, 0, windWidth, 132);
  const elapsed = Math.max(0, time - flowStarted - 1100);
  const sweep = state.airflow === 'vertical' && !reducedMotion.matches ? Math.sin(elapsed * Math.PI * 2 / 4200) : 0;
  byId('flap-blade').style.transform = `scaleY(${1 - sweep * .25})`;
  const speed = ({ auto: .00045, low: .0003, middle: .00045, high: .00065, strong: .00085, mute: .00022 })[state.fan];
  for (let i = 0; i < 32; i++) {
    const u = i / 31;
    const originX = windWidth / 2 - 62 + u * 124;
    const originY = 47 + u * 11;
    const spread = (u - .5) * (53 + sweep * 14);
    const length = 64 + sweep * 14;
    const progress = (time * speed + i * .173) % 1;
    const gradient = context.createLinearGradient(0, originY, 0, originY + length);
    gradient.addColorStop(0, 'rgba(216,230,219,0)');
    gradient.addColorStop(.15, 'rgba(224,238,229,.12)');
    gradient.addColorStop(.55, 'rgba(224,238,229,.07)');
    gradient.addColorStop(1, 'rgba(216,230,219,0)');
    context.strokeStyle = gradient;
    context.lineWidth = 1.1;
    context.beginPath();
    context.moveTo(originX, originY);
    context.bezierCurveTo(originX, originY + 17, originX + spread * .7, originY + length * .75, originX + spread, originY + length);
    context.stroke();
    context.beginPath();
    for (let j = 0; j <= 8; j++) {
      const t = Math.max(0, progress - .17 + j * .021);
      const bend = Math.sin(t * Math.PI / 2);
      const x = originX + spread * bend + Math.sin(t * 7 + i) * 1.7 * t;
      const y = originY + length * t;
      if (j === 0) context.moveTo(x, y); else context.lineTo(x, y);
    }
    const opacity = Math.sin(progress * Math.PI) * .46;
    context.strokeStyle = `rgba(224,238,229,${opacity})`;
    context.lineWidth = 1.5 + Math.sin(i * 2) * .4;
    context.stroke();
  }
}

function animate(time) {
  animationFrame = 0;
  if (!state.power || showingSettings || document.hidden || reducedMotion.matches) return;
  drawWind(time);
  animationFrame = requestAnimationFrame(animate);
}

function updateAnimation() {
  if (!state.power || showingSettings || document.hidden || reducedMotion.matches) {
    cancelAnimationFrame(animationFrame);
    animationFrame = 0;
    if (!state.power) { flowStarted = 0; byId('flap-blade').style.transform = 'scaleY(1)'; }
    if (state.power && !showingSettings && !document.hidden) drawWind(0);
    return;
  }
  if (!flowStarted) flowStarted = performance.now();
  if (!animationFrame) animationFrame = requestAnimationFrame(animate);
}

function render() {
  panel.setAttribute('aria-busy', String(busy));
  controls.forEach(control => { control.disabled = busy; });
  byId('power-button').setAttribute('aria-pressed', String(state.power));
  byId('power-button').setAttribute('aria-label', state.power ? 'Apagar aire' : 'Encender aire');
  byId('temperature').textContent = state.temperature;
  byId('temperature-slider').value = state.temperature;
  byId('temperature-slider').setAttribute('aria-valuetext', `${state.temperature} °C`);
  byId('temperature-slider').style.setProperty('--fill', `${(state.temperature - 16) / 16 * 100}%`);
  byId('temperature-down').disabled = busy || state.temperature <= 16;
  byId('temperature-up').disabled = busy || state.temperature >= 32;
  byId('temperature-down').classList.toggle('at-limit', state.temperature <= 16);
  byId('temperature-up').classList.toggle('at-limit', state.temperature >= 32);
  modeButton.setAttribute('aria-label', `Modo actual: ${modes[state.mode]}. Elegir modo`);
  byId('mode-icon-use').setAttribute('href', modeIcons[state.mode]);
  byId('mode-label').textContent = modes[state.mode];
  modeButtons.forEach(button => {
    button.setAttribute('aria-pressed', String(button.dataset.mode === state.mode));
    button.setAttribute('aria-disabled', String(busy));
  });
  fanSlider.value = fanOrder.indexOf(state.fan);
  // Keep keyboard focus while synchronization temporarily blocks slider edits.
  fanSlider.setAttribute('aria-disabled', String(busy));
  fanSlider.setAttribute('aria-valuetext', fans[state.fan]);
  fanSlider.parentElement.style.setProperty('--fan-progress', fanOrder.indexOf(state.fan) / (fanOrder.length - 1));
  byId('fan-label').textContent = fans[state.fan];
  document.querySelectorAll('.fan-steps span').forEach((step, index) => {
    step.style.left = `${index / (fanOrder.length - 1) * 100}%`;
    step.classList.toggle('is-active', step.dataset.fan === state.fan);
  });
  byId('sleep-button').setAttribute('aria-pressed', String(state.sleep));
  byId('sleep-button').setAttribute('aria-label', state.sleep ? 'Modo Sueño activado' : 'Modo Sueño apagado');
  byId('oscillation-button').setAttribute('aria-pressed', String(state.airflow === 'vertical'));
  byId('oscillation-button').setAttribute('aria-label', state.airflow === 'vertical' ? 'Desactivar oscilación vertical' : 'Activar oscilación vertical');
  byId('mini-display-value').textContent = state.temperature;
  byId('mini-display').disabled = busy || !state.power;
  byId('mini-display').setAttribute('aria-pressed', String(state.light));
  byId('mini-display').setAttribute('aria-label', state.light ? 'Apagar display del minisplit' : 'Encender display del minisplit');
  byId('mini-display').setAttribute('data-lit', String(state.power && state.light));
  byId('connected-icon').toggleAttribute('hidden', busy);
  byId('sync-spinner').hidden = !busy;
  byId('connection-status').textContent = busy ? 'Sincronizando…' : 'Conectado';
  scene.setAttribute('data-power', String(state.power));
  scene.setAttribute('data-airflow', state.airflow);
  scene.setAttribute('aria-label', !state.power ? 'Minisplit apagado, aspa cerrada' : state.airflow === 'vertical' ? 'Minisplit encendido con oscilación vertical' : 'Minisplit encendido con aspa fija');
  updateAnimation();
}

async function action(change) {
  if (busy) return;
  change();
  busy = true;
  render();
  await new Promise(resolve => setTimeout(resolve, 650));
  busy = false;
  render();
}

function setFanPopover(open) {
  if (open && busy) return;
  const expanded = Boolean(open);
  if (expanded) setModeOptions(false);
  fanPopover.hidden = !expanded;
  fanButton.setAttribute('aria-expanded', String(expanded));
  fanControl.classList.toggle('is-open', expanded);
}

function setModeOptions(open) {
  if (open && busy) return;
  const expanded = Boolean(open);
  if (expanded) setFanPopover(false);
  modeOptions.hidden = !expanded;
  modeButton.setAttribute('aria-expanded', String(expanded));
  modeControl.classList.toggle('is-open', expanded);
}

function setSettingsScreen(open) {
  if (open && busy) return;
  showingSettings = Boolean(open);
  setFanPopover(false);
  setModeOptions(false);
  controlsScreen.hidden = showingSettings;
  controlsScreen.inert = showingSettings;
  settingsScreen.hidden = !showingSettings;
  settingsScreen.inert = !showingSettings;
  panel.setAttribute('aria-label', showingSettings ? 'Configuración de Mi X5' : 'Control de Mi X5');
  if (!showingSettings) {
    byId('local-key').type = 'password';
    byId('show-key').setAttribute('aria-label', 'Mostrar clave');
  }
  resizePreview();
  byId(showingSettings ? 'settings-back' : 'settings-button').focus();
}

modeControl.onpointerenter = event => { if (event.pointerType === 'mouse') setModeOptions(true); };
modeControl.onpointerleave = event => { if (event.pointerType === 'mouse') setModeOptions(false); };
modeControl.onfocusin = event => { if (event.target.matches(':focus-visible')) setModeOptions(true); };
modeControl.onfocusout = event => {
  if (!modeControl.contains(event.relatedTarget) && !modeControl.matches(':hover')) setModeOptions(false);
};
modeControl.onkeydown = event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    modeButton.focus();
    setModeOptions(false);
  }
};
modeButton.onclick = event => {
  if (event.detail === 0 || !matchMedia('(hover: hover)').matches) setModeOptions(modeOptions.hidden);
};
modeButtons.forEach(button => {
  button.onclick = () => {
    const next = button.dataset.mode;
    if (!Object.hasOwn(modes, next) || next === state.mode) return;
    return action(() => { state.mode = next; });
  };
});

fanControl.onpointerenter = event => { if (event.pointerType === 'mouse') setFanPopover(true); };
fanControl.onpointerleave = event => { if (event.pointerType === 'mouse') setFanPopover(false); };
fanControl.onfocusin = event => { if (event.target.matches(':focus-visible')) setFanPopover(true); };
fanControl.onfocusout = event => {
  if (!fanControl.contains(event.relatedTarget) && !fanControl.matches(':hover')) setFanPopover(false);
};
fanControl.onkeydown = event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    fanButton.focus();
    setFanPopover(false);
  }
};
fanButton.onclick = event => {
  if (event.detail === 0 || !matchMedia('(hover: hover)').matches) setFanPopover(fanPopover.hidden);
};
fanSlider.oninput = event => {
  const next = fanOrder[Number(event.target.value)];
  if (busy || !next) { render(); return; }
  if (next === state.fan) return;
  const direction = Math.sign(fanOrder.indexOf(next) - fanOrder.indexOf(state.fan));
  state.fan = next;
  render();
  if (!reducedMotion.matches) {
    fanHop?.cancel();
    fanHop = fanKnob.animate([
      { transform: 'translate(-50%, -50%) scale(.85)' },
      { transform: `translate(-50%, -50%) translateX(${direction * 5}px) scale(1.08)`, offset: .65 },
      { transform: 'translate(-50%, -50%) scale(1)' },
    ], { duration: 280, easing: 'ease-out' });
  }
};
fanSlider.onchange = () => { if (busy) { render(); return; } return action(() => {}); };

byId('power-button').onclick = () => action(() => { state.power = !state.power; });
byId('temperature-down').onclick = () => action(() => { state.temperature = Math.max(16, state.temperature - 1); });
byId('temperature-up').onclick = () => action(() => { state.temperature = Math.min(32, state.temperature + 1); });
byId('temperature-slider').oninput = event => { state.temperature = Number(event.target.value); render(); };
byId('temperature-slider').onchange = () => action(() => {});
byId('sleep-button').onclick = () => action(() => { state.sleep = !state.sleep; });
byId('oscillation-button').onclick = () => action(() => { state.airflow = state.airflow === 'vertical' ? 'fixed' : 'vertical'; });
byId('mini-display').onclick = () => action(() => { state.light = !state.light; });
byId('settings-button').onclick = () => setSettingsScreen(true);
byId('settings-back').onclick = byId('cancel-settings').onclick = () => setSettingsScreen(false);
settingsScreen.onkeydown = event => {
  if (event.key === 'Escape') { event.preventDefault(); setSettingsScreen(false); }
};
byId('connection-form').onsubmit = event => { event.preventDefault(); setSettingsScreen(false); return action(() => {}); };
byId('show-key').onclick = () => {
  const key = byId('local-key');
  key.type = key.type === 'password' ? 'text' : 'password';
  byId('show-key').setAttribute('aria-label', key.type === 'password' ? 'Mostrar clave' : 'Ocultar clave');
};
window.addEventListener('resize', resizePreview);
document.addEventListener('visibilitychange', updateAnimation);
reducedMotion.addEventListener('change', updateAnimation);
resizePreview();
render();

// Browser self-check: open index.html#check; normal previews do not run it.
if (location.hash === '#check') {
  (async () => {
    const assert = (condition, message) => { if (!condition) throw new Error(message); };
    const original = { ...state };
    const panelBounds = panel.getBoundingClientRect();
    const frameBounds = byId('panel-frame').getBoundingClientRect();
    const edge = panel.dataset.trayEdge;
    assert(Math.abs(frameBounds.left - (panelBounds.left - (edge === 'left' ? 16 : 0))) < .5 &&
      Math.abs(frameBounds.right - (panelBounds.right + (edge === 'right' ? 16 : 0))) < .5 &&
      Math.abs(frameBounds.top - (panelBounds.top - (edge === 'top' ? 16 : 0))) < .5 &&
      Math.abs(frameBounds.bottom - (panelBounds.bottom + (edge === 'bottom' ? 16 : 0))) < .5, 'Background fits the panel and points toward the tray');
    const hingeStyle = getComputedStyle(byId('flap-blade').parentElement);
    const pivotY = parseFloat(hingeStyle.transformOrigin.split(' ')[1]);
    assert(Math.abs(pivotY - parseFloat(hingeStyle.height)) < .1, 'Lower edge remains anchored');
    state.temperature = 16; render();
    byId('temperature-down').click();
    assert(state.temperature === 16 && !busy, 'Minimum temperature');
    state.temperature = 32; render();
    byId('temperature-up').click();
    assert(state.temperature === 32 && !busy, 'Maximum temperature');
    Object.assign(state, original); render();
    const before = byId('settings-button').getBoundingClientRect();
    const operation = action(() => { state.power = false; });
    assert(byId('connection-status').textContent === 'Sincronizando…' && !byId('sync-spinner').hidden, 'Loading status');
    assert(scene.getAttribute('data-power') === 'false' && !animationFrame, 'Air stops when powered off');
    assert(byId('mini-display').disabled && byId('mini-display').getAttribute('data-lit') === 'false', 'Display stays dark while the air is off');
    const during = byId('settings-button').getBoundingClientRect();
    assert(before.x === during.x && before.y === during.y, 'Stable footer');
    await operation;
    assert(byId('sync-spinner').hidden && byId('connection-status').textContent === 'Conectado', 'Connected status restored');
    await action(() => { state.power = true; state.airflow = 'fixed'; });
    assert(scene.getAttribute('data-power') === 'true' && scene.getAttribute('data-airflow') === 'fixed', 'Air starts with fixed vane');
    await byId('oscillation-button').onclick();
    assert(scene.getAttribute('data-airflow') === 'vertical' && byId('oscillation-button').getAttribute('aria-pressed') === 'true', 'Button starts vertical oscillation');
    await byId('oscillation-button').onclick();
    assert(scene.getAttribute('data-airflow') === 'fixed' && byId('oscillation-button').getAttribute('aria-pressed') === 'false', 'Button fixes the vane');
    await byId('oscillation-button').onclick();
    setFanPopover(false);
    setModeOptions(false);
    await new Promise(resolve => setTimeout(resolve, 420));
    const modeBefore = modeControl.getBoundingClientRect();
    const fanBefore = fanControl.getBoundingClientRect();
    const fanBackground = getComputedStyle(byId('fan-expandable')).backgroundColor;
    fanControl.dispatchEvent(new PointerEvent('pointerenter', { pointerType: 'mouse' }));
    assert(!fanPopover.hidden && fanButton.getAttribute('aria-expanded') === 'true', 'Fan opens on hover');
    await new Promise(resolve => setTimeout(resolve, 420));
    const fanExpanded = fanControl.getBoundingClientRect();
    assert(fanExpanded.width > fanBefore.width && modeControl.getBoundingClientRect().width < modeBefore.width, 'Fan borrows width from Mode');
    assert(Math.abs(fanExpanded.top - fanBefore.top) < .5 && Math.abs(fanExpanded.height - fanBefore.height) < .5 && Math.abs(fanExpanded.right - fanBefore.right) < .5, 'Fan keeps its vertical position, height and right edge');
    assert(getComputedStyle(byId('fan-expandable')).backgroundColor === fanBackground, 'Fan keeps the original background');
    assert(byId('fan-slider').getBoundingClientRect().bottom <= fanExpanded.bottom, 'Slider fits inside the card');
    assert(fanOrder.join(',') === 'auto,mute,low,middle,high,strong', 'Fan positions from Auto to Turbo');
    for (let index = 0; index < fanOrder.length; index++) {
      fanSlider.value = index;
      fanSlider.dispatchEvent(new Event('input', { bubbles: true }));
      assert(state.fan === fanOrder[index] && byId('fan-label').textContent === fans[state.fan], 'Fan slider selection');
      assert(fanSlider.getAttribute('aria-valuetext') === fans[state.fan], 'Accessible fan value');
      await fanSlider.onchange();
    }
    fanSlider.focus();
    fanControl.dispatchEvent(new PointerEvent('pointerleave', { pointerType: 'mouse' }));
    assert(fanPopover.hidden && fanButton.getAttribute('aria-expanded') === 'false', 'Fan closes when pointer leaves, even after selection');
    await new Promise(resolve => setTimeout(resolve, 420));
    assert(Math.abs(fanControl.getBoundingClientRect().width - fanBefore.width) < .5 && Math.abs(modeControl.getBoundingClientRect().width - modeBefore.width) < .5, 'Card widths return after closing');
    fanButton.click();
    assert(!fanPopover.hidden, 'Keyboard can open the fan slider');
    fanSlider.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    assert(fanPopover.hidden && document.activeElement === fanButton, 'Escape closes and restores focus');
    const modeBackground = getComputedStyle(byId('mode-expandable')).backgroundColor;
    modeControl.dispatchEvent(new PointerEvent('pointerenter', { pointerType: 'mouse' }));
    assert(!modeOptions.hidden && fanPopover.hidden, 'Mode opens on hover and closes Fan');
    await new Promise(resolve => setTimeout(resolve, 420));
    const modeExpanded = modeControl.getBoundingClientRect();
    assert(modeExpanded.width > modeBefore.width && fanControl.getBoundingClientRect().width < fanBefore.width, 'Mode borrows width from Fan');
    assert(Math.abs(modeExpanded.top - modeBefore.top) < .5 && Math.abs(modeExpanded.height - modeBefore.height) < .5 && Math.abs(modeExpanded.left - modeBefore.left) < .5, 'Mode keeps its vertical position, height and left edge');
    assert(getComputedStyle(byId('mode-expandable')).backgroundColor === modeBackground, 'Mode keeps the original background');
    assert(modeOptions.getBoundingClientRect().bottom <= modeExpanded.bottom, 'Mode choices fit inside the card');
    assert(modeButtons.map(button => button.dataset.mode).join(',') === 'cold,auto,wet,wind', 'Four cooling-only modes');
    for (const button of modeButtons) {
      await button.onclick();
      assert(state.mode === button.dataset.mode && button.getAttribute('aria-pressed') === 'true', 'Mode icon selection');
      assert(byId('mode-label').textContent === modes[state.mode] && byId('mode-icon-use').getAttribute('href') === modeIcons[state.mode], 'Mode header follows the selection');
    }
    modeControl.dispatchEvent(new PointerEvent('pointerleave', { pointerType: 'mouse' }));
    assert(modeOptions.hidden, 'Mode closes when pointer leaves');
    modeButton.click();
    assert(!modeOptions.hidden && fanPopover.hidden, 'Keyboard opens only Mode');
    modeControl.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    assert(modeOptions.hidden && document.activeElement === modeButton, 'Escape closes Mode and restores focus');
    for (const enabled of [true, false]) {
      await byId('sleep-button').onclick();
      assert(state.sleep === enabled &&
        byId('sleep-button').getAttribute('aria-pressed') === String(enabled), 'Sleep on / off toggle');
      assert(byId('sleep-button').getAttribute('aria-label') === (enabled ? 'Modo Sueño activado' : 'Modo Sueño apagado'), 'Accessible Sleep state');
    }
    for (const enabled of [false, true]) {
      await byId('mini-display').onclick();
      assert(state.light === enabled, 'Display button changes the light');
      assert(byId('mini-display').getAttribute('data-lit') === String(enabled) && !byId('mini-display').hidden, 'Display remains clickable when dark');
      assert(byId('mini-display-value').textContent === String(state.temperature), 'Display shows the current temperature');
    }
    const boundsBeforeSettings = panel.getBoundingClientRect();
    const lightBeforeSettings = state.light;
    byId('settings-button').onclick();
    assert(controlsScreen.hidden && controlsScreen.inert && !settingsScreen.hidden && !settingsScreen.inert, 'Settings replaces the controls inside the panel');
    assert(document.activeElement === byId('settings-back') && !animationFrame, 'Settings receives focus and pauses the hidden animation');
    await new Promise(resolve => setTimeout(resolve, 260));
    const settingsBounds = panel.getBoundingClientRect();
    assert(Math.abs(settingsBounds.width - boundsBeforeSettings.width) < .5 && Math.abs(settingsBounds.height - boundsBeforeSettings.height) < .5, 'Navigation keeps the panel size');
    byId('settings-back').onclick();
    assert(!controlsScreen.hidden && settingsScreen.hidden && document.activeElement === byId('settings-button'), 'Back returns to controls and restores focus');
    assert(state.light === lightBeforeSettings && !document.getElementById('display-light'), 'Display control exists only on the main screen');
    assert(!document.querySelector('[title]'), 'No hover tooltips');
    Object.assign(state, original); render();
    byId('check-result').hidden = false;
    byId('check-result').textContent = 'Comprobaciones correctas';
  })().catch(error => {
    byId('check-result').hidden = false;
    byId('check-result').textContent = `Error: ${error.message}`;
    console.error(error);
  });
}
