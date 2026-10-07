'use strict';

const demo = document.querySelector('#product-demo');
if (demo) {
    const duration = 14, exampleDuration = 7;
    const examples = [
        { text: 'An idea for the next design review', action: 'Save to Notes' },
        { text: 'Remind me to send the design draft', action: 'Save to Reminders' },
    ];
    const motion = matchMedia('(prefers-reduced-motion: reduce)');
    const get = id => demo.querySelector(`#demo-${id}`);
    const panel = get('panel'), body = get('body'), text = get('text');
    const placeholder = get('placeholder'), caret = get('caret'), target = get('target');
    const title = get('action-title'), returnKey = get('return'), intent = get('intent');
    const pointer = get('pointer'), click = get('click'), canvas = get('wind');
    const context = canvas.getContext('2d'), status = get('status');
    const clamp = value => Math.max(0, Math.min(1, value));
    const mix = (a, b, t) => a + (b - a) * t;
    const smooth = value => { const p = clamp(value); return p * p * (3 - 2 * p); };
    const ramp = (t, start, end) => smooth((t - start) / (end - start));
    const px = value => `${value.toFixed(3)}px`;
    let bounds = { width: demo.clientWidth, height: demo.clientHeight };
    let elapsed = 0, frameID = 0, lastFrame = null;
    let paused = false, inView = false, pageActive = true;
    let currentScene, textureCache = null;

    // Closed-form critically damped responses, summed for each target change.
    // No integration or frame history is needed, including across a loop seam.
    function spring(t, rate = 19) {
        return t <= 0 ? 0 : 1 - (1 + rate * t) * Math.exp(-rate * t);
    }
    function track(t, initial, changes, rate = 19) {
        let value = initial;
        for (const period of [-1, 0]) {
            let previous = initial;
            for (const [at, next] of changes) {
                value += (next - previous) * spring(t - at - period * exampleDuration, rate);
                previous = next;
            }
        }
        return value;
    }

    function geometry(t) {
        const { width, height } = bounds;
        const bodyHeight = width < 400 ? 132 : 148;
        // Change geometry rather than scaling a text bitmap.
        const framing = track(t, .96, [[.5, 1], [6, .96]], 15);
        const w = Math.min(510, width - 28) * framing;
        return { w, h: bodyHeight, x: (width - w) / 2, y: (height - bodyHeight) / 2, bodyHeight };
    }

    function sceneAt(seconds) {
        const t = ((seconds % duration) + duration) % duration;
        const index = Math.floor(t / exampleDuration), phase = t % exampleDuration;
        const example = examples[index], g = geometry(phase);
        const content = phase >= 6 ? '' : example.text.slice(0, Math.floor(clamp((phase - .5) / 2) * example.text.length));
        const ready = phase >= 3 && phase < 6;
        const labelReveal = ramp(phase, 3, 3.16);
        const draft = geometry(.5);
        const rest = [bounds.width * .21, bounds.height * .26];
        const moves = [[0, [draft.x + 62, draft.y + 36]],
            [3.5, [bounds.width * .8, bounds.height * .76]], [6, rest]];
        const cursorX = track(phase, rest[0], moves.map(([at, p]) => [at, p[0]]), 15);
        const cursorY = track(phase, rest[1], moves.map(([at, p]) => [at, p[1]]), 15);
        const sinceClick = phase - .5, clickProgress = clamp(sinceClick / .32);
        const clickOpacity = sinceClick >= 0 && sinceClick < .32 ? Math.sin(clickProgress * Math.PI) * .55 : 0;
        const press = sinceClick >= 0 && sinceClick < .2 ? Math.sin(sinceClick / .2 * Math.PI) : 0;
        return { t, phase, index, ...g, text: content, action: example.action, ready, labelReveal,
            cursorX, cursorY, press, clickProgress, clickOpacity,
            keyPress: ramp(phase, 4.5, 4.6) - ramp(phase, 4.75, 4.9),
            caretOpacity: (phase < 3 || phase >= 6.35) && t % 1 < .65 ? 1 : 0,
            intent: phase >= 2.5 && phase < 3 ? 'Understanding…' : '',
            panelOpacity: phase >= 5 && phase < 6 ? 0 : phase >= 6 ? ramp(phase, 6, 6.35) : 1,
            wind: phase >= 5 && phase < 5.5 ? (phase - 5) / .5 : -1,
            state: phase >= 6 ? 'opening' : phase >= 4.5 ? 'submitting' : ready ? 'ready' : content ? 'typing' : 'empty' };
    }

    function draw(s) {
        currentScene = s;
        demo.dataset.state = s.state;
        demo.dataset.beat = Math.floor(s.t * 2) + 1;
        panel.style.left = px(s.x);
        panel.style.top = px(s.y);
        panel.style.width = px(s.w);
        panel.style.height = px(s.h);
        panel.style.opacity = s.panelOpacity;
        panel.setAttribute('aria-hidden', String(s.panelOpacity < .5));
        body.style.height = px(s.bodyHeight);
        text.textContent = s.text;
        placeholder.hidden = Boolean(s.text);
        caret.style.opacity = s.caretOpacity;
        intent.textContent = s.intent;
        target.hidden = !s.ready;
        title.textContent = s.action;
        title.style.opacity = s.labelReveal.toFixed(4);
        title.style.filter = `blur(${px((1 - s.labelReveal) * 3)})`;
        returnKey.style.backgroundColor = `rgba(36, 91, 236, ${mix(.08, 1, s.keyPress).toFixed(3)})`;
        returnKey.style.color = s.keyPress > .5 ? '#fff' : '#245bec';
        returnKey.style.transform = `translateY(${px(s.keyPress)})`;
        target.setAttribute('aria-label', `Suggested Action: ${s.action}. Press Enter to confirm.`);
        const pixelRatio = devicePixelRatio || 1;
        pointer.style.left = px(Math.round(s.cursorX * pixelRatio) / pixelRatio);
        pointer.style.top = px(Math.round(s.cursorY * pixelRatio) / pixelRatio);
        pointer.style.transform = `scale(${(1 - s.press * .14).toFixed(4)})`;
        pointer.style.opacity = motion.matches ? '0' : '1';
        click.style.left = px(s.cursorX);
        click.style.top = px(s.cursorY);
        click.style.transform = `translate(-50%, -50%) scale(${mix(.4, 1.4, s.clickProgress).toFixed(4)})`;
        click.style.opacity = motion.matches ? '0' : s.clickOpacity.toFixed(4);
    }

    function captureTexture() {
        const rect = panel.getBoundingClientRect();
        const scale = Math.min(devicePixelRatio || 1, 2);
        const texture = document.createElement('canvas');
        texture.width = Math.ceil(rect.width * scale);
        texture.height = Math.ceil(rect.height * scale);
        const paint = texture.getContext('2d');
        if (!paint) return null;
        paint.scale(scale, scale);
        function surface(element) {
            if (element.hidden || getComputedStyle(element).display === 'none') return;
            const r = element.getBoundingClientRect(), css = getComputedStyle(element);
            const line = parseFloat(css.borderTopWidth) || 0;
            paint.beginPath();
            paint.roundRect(r.left - rect.left + line / 2, r.top - rect.top + line / 2,
                r.width - line, r.height - line, Math.min(parseFloat(css.borderRadius) || 0, r.height / 2));
            paint.fillStyle = css.backgroundColor;
            paint.fill();
            if (line) { paint.lineWidth = line; paint.strokeStyle = css.borderTopColor; paint.stroke(); }
        }
        function lettering(element) {
            const node = element.firstChild;
            if (!node || node.nodeType !== Node.TEXT_NODE) return;
            const css = getComputedStyle(element);
            paint.font = `${css.fontWeight} ${css.fontSize} ${css.fontFamily}`;
            paint.fillStyle = css.color;
            const metrics = paint.measureText(node.textContent);
            const ascent = metrics.fontBoundingBoxAscent ?? parseFloat(css.fontSize) * .8;
            const descent = metrics.fontBoundingBoxDescent ?? parseFloat(css.fontSize) * .2;
            const range = document.createRange();
            for (let i = 0; i < node.length; i++) {
                range.setStart(node, i); range.setEnd(node, i + 1);
                const r = range.getBoundingClientRect();
                paint.fillText(node.textContent[i], r.left - rect.left,
                    r.top - rect.top + (r.height - ascent - descent) / 2 + ascent);
            }
        }
        surface(panel); surface(target); surface(returnKey);
        lettering(text); lettering(title);
        const r = returnKey.getBoundingClientRect();
        paint.strokeStyle = '#245bec'; paint.lineWidth = 1.2;
        paint.lineCap = 'round'; paint.lineJoin = 'round';
        const x = r.left - rect.left + 1, y = r.top - rect.top + 1;
        paint.beginPath();
        paint.moveTo(x + 12, y + 3.2); paint.lineTo(x + 12, y + 8.8); paint.lineTo(x + 4, y + 8.8);
        paint.moveTo(x + 7.2, y + 5.6); paint.lineTo(x + 4, y + 8.8); paint.lineTo(x + 7.2, y + 12);
        paint.stroke();
        canvas.width = Math.ceil(bounds.width * scale);
        canvas.height = Math.ceil(bounds.height * scale);
        context?.setTransform(scale, 0, 0, scale, 0, 0);
        return { texture, scale, width: rect.width, height: rect.height,
            x: currentScene.x, y: currentScene.y };
    }

    function drawWind(snapshot, progress) {
        const { texture, scale, width, height, x, y } = snapshot;
        context.clearRect(0, 0, bounds.width, bounds.height);
        const cell = Math.max(4, Math.sqrt(width * height / 1800));
        const columns = Math.ceil(width / cell), rows = Math.ceil(height / cell);
        const cw = width / columns, ch = height / rows;
        for (let row = 0; row < rows; row++) for (let column = 0; column < columns; column++) {
            const noise = Math.sin(column * 127.1 + row * 311.7) * 43758.5453;
            const flutterNoise = Math.sin(column * 269.5 + row * 183.3) * 24634.6345;
            const seed = noise - Math.floor(noise), flutter = flutterNoise - Math.floor(flutterNoise);
            const delay = (1 - column / (columns - 1)) * .54 + seed * .13;
            const p = clamp((progress - delay) / .33);
            if (p >= 1) continue;
            const drift = p * .7 + p * p * .3;
            const size = 1 - smooth(p) * .78;
            context.save();
            context.globalAlpha = 1 - smooth((p - .18) / .82);
            context.translate(x + (column + .5) * cw + (34 + seed * 46) * drift,
                y + (row + .5) * ch - (8 + flutter * 27) * p + Math.sin(p * Math.PI * 2 + seed * Math.PI * 2) * p * 5);
            context.rotate((flutter - .5) * p * 2.2);
            context.scale(size, size * (1 - Math.sin(p * Math.PI) * flutter * .35));
            context.drawImage(texture, column * cw * scale, row * ch * scale, cw * scale, ch * scale,
                -cw / 2, -ch / 2, cw, ch);
            context.restore();
        }
    }

    function present(scene) {
        canvas.hidden = scene.wind < 0 || !context || motion.matches;
        if (!canvas.hidden) {
            // The fixed pre-exit frame also supports a first seek into particles.
            const key = `${bounds.width}:${bounds.height}:${scene.index}:${document.fonts.status}`;
            if (textureCache?.key !== key) {
                draw(sceneAt(scene.index * exampleDuration + 4.99));
                textureCache = { key, snapshot: captureTexture() };
            }
            if (textureCache.snapshot) drawWind(textureCache.snapshot, scene.wind);
        }
        draw(scene);
    }
    function render() { present(sceneAt(elapsed)); }
    function frame(now) {
        frameID = 0;
        if (lastFrame !== null) elapsed = (elapsed + (now - lastFrame) / 1000) % duration;
        lastFrame = now;
        render();
        frameID = requestAnimationFrame(frame);
    }
    function syncPlayback() {
        cancelAnimationFrame(frameID);
        frameID = 0;
        lastFrame = null;
        const running = !paused && inView && pageActive && !document.hidden && !motion.matches;
        demo.dataset.playback = running ? 'playing' : 'paused';
        if (running) frameID = requestAnimationFrame(frame);
    }
    function togglePause() {
        if (motion.matches) return;
        paused = !paused;
        status.textContent = paused ? 'Demo paused. Press Space to resume.' : 'Demo playing.';
        syncPlayback();
    }
    function submit() {
        if (!currentScene.ready || currentScene.phase >= 4.5 || currentScene.panelOpacity < .5) return;
        elapsed = currentScene.index * exampleDuration + (motion.matches ? 3.5 : 4.5);
        paused = motion.matches;
        render();
        syncPlayback();
        status.textContent = 'Example submitted. Jotway would return you to your work. This is not a save confirmation.';
    }
    demo.addEventListener('click', togglePause);
    demo.addEventListener('keydown', event => {
        if (event.isComposing) return;
        if (event.key === 'Escape') {
            event.preventDefault();
            paused = true;
            syncPlayback();
            status.textContent = 'Demo paused.';
        } else if (event.key === ' ') { event.preventDefault(); togglePause(); }
        else if (event.key === 'Enter') { event.preventDefault(); submit(); }
    });
    motion.addEventListener('change', () => {
        elapsed = motion.matches ? 3.5 : 0;
        render();
        syncPlayback();
    });
    document.addEventListener('visibilitychange', syncPlayback);
    window.addEventListener('pagehide', () => { pageActive = false; syncPlayback(); });
    window.addEventListener('pageshow', () => { pageActive = true; syncPlayback(); });
    new IntersectionObserver(entries => {
        inView = entries[0].isIntersecting;
        syncPlayback();
    }, { threshold: .15 }).observe(demo);
    new ResizeObserver(() => {
        bounds = { width: demo.clientWidth, height: demo.clientHeight };
        textureCache = null;
        render();
    }).observe(demo);
    window.jotwayDemo = Object.freeze({
        duration,
        seek(seconds) {
            if (!Number.isFinite(seconds)) return;
            paused = true;
            elapsed = seconds;
            present(sceneAt(seconds));
            syncPlayback();
        },
        play() { paused = false; syncPlayback(); },
        pause() { paused = true; syncPlayback(); },
    });
    elapsed = motion.matches ? 3.5 : 0;
    demo.dataset.ready = 'true';
    render();
    syncPlayback();
}

const copyButton = document.querySelector('#copy-checksum');
copyButton?.addEventListener('click', async () => {
    const status = document.querySelector('#copy-status');
    try {
        await navigator.clipboard.writeText(document.querySelector('#checksum').textContent.trim());
        status.textContent = 'Checksum copied.';
    } catch {
        status.textContent = 'Copy unavailable. Select the checksum above and copy it manually.';
    }
});
