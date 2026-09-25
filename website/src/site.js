'use strict';

const demo = document.querySelector('#product-demo');
if (demo) {
    const examples = [
        { text: 'notes: a quiet weekend in Kyoto', action: 'Save to Notes' },
        { text: 'remind me to send the design draft', action: 'Save to Reminders' },
        { text: 'search macOS keyboard shortcuts', action: 'Google Search' },
        { text: 'add to calendar: design discussion', action: 'Save to Calendar' },
        { text: 'notes: an idea for my next side project', action: 'Save to Notes' },
        { text: 'remind me to water the plants', action: 'Save to Reminders' },
        { text: 'search quiet cafes in Kyoto', action: 'Google Search' },
    ];
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const panel = demo.querySelector('#demo-panel');
    const text = demo.querySelector('#demo-text');
    const placeholder = demo.querySelector('#demo-placeholder');
    const confirm = demo.querySelector('#demo-confirm');
    const actionTitle = demo.querySelector('#demo-action-title');
    const status = demo.querySelector('#demo-status');
    const canvas = demo.querySelector('#demo-wind');
    const context = canvas.getContext('2d');
    const clamp = value => Math.max(0, Math.min(1, value));
    const smooth = value => { const t = clamp(value); return t * t * (3 - 2 * t); };
    let selected = 0;
    let state = motion.matches ? 'suggesting' : 'idle';
    let elapsed = 0;
    let frameID = 0;
    let lastFrame = null;
    let paused = false;
    let inView = true;
    let snapshot = null;

    function render() {
        const example = examples[selected];
        demo.dataset.state = state;
        panel.setAttribute('aria-hidden', String(state === 'dissolving' || state === 'completed'));
        text.textContent = state === 'idle' ? '' : state === 'typing'
            ? example.text.slice(0, Math.floor(elapsed / 48)) : example.text;
        placeholder.hidden = state !== 'idle';
        actionTitle.textContent = example.action;
        confirm.disabled = state !== 'suggesting';
        canvas.hidden = state !== 'dissolving' || !snapshot;
        if (confirm.disabled && document.activeElement === confirm) demo.focus({ preventScroll: true });
    }

    function setState(next) {
        state = next;
        elapsed = 0;
        render();
    }

    // Rebuild the card's texture from its actual layout, including wrapped text and
    // the Action button. Every particle samples this one continuous surface.
    function capturePanel() {
        if (!context) return null;
        const bounds = panel.getBoundingClientRect();
        const scale = Math.min(window.devicePixelRatio || 1, 2);
        const texture = document.createElement('canvas');
        texture.width = Math.ceil(bounds.width * scale);
        texture.height = Math.ceil(bounds.height * scale);
        const paint = texture.getContext('2d');
        if (!paint) return null;
        paint.scale(scale, scale);

        function surface(element) {
            const rect = element.getBoundingClientRect();
            const style = getComputedStyle(element);
            const line = parseFloat(style.borderTopWidth) || 0;
            paint.beginPath();
            paint.roundRect(rect.left - bounds.left + line / 2, rect.top - bounds.top + line / 2,
                rect.width - line, rect.height - line, parseFloat(style.borderRadius) || 0);
            paint.fillStyle = style.backgroundColor;
            paint.fill();
            if (line) {
                paint.strokeStyle = style.borderTopColor;
                paint.lineWidth = line;
                paint.stroke();
            }
        }

        function lettering(element) {
            const node = element.firstChild;
            if (!node || node.nodeType !== Node.TEXT_NODE) return;
            const style = getComputedStyle(element);
            paint.font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
            paint.fillStyle = style.color;
            const metrics = paint.measureText(node.textContent);
            const ascent = metrics.fontBoundingBoxAscent ?? parseFloat(style.fontSize) * .8;
            const descent = metrics.fontBoundingBoxDescent ?? parseFloat(style.fontSize) * .2;
            const range = document.createRange();
            for (let i = 0; i < node.length; i++) {
                range.setStart(node, i);
                range.setEnd(node, i + 1);
                const rect = range.getBoundingClientRect();
                paint.fillText(node.textContent[i], rect.left - bounds.left,
                    rect.top - bounds.top + (rect.height - ascent - descent) / 2 + ascent);
            }
        }

        surface(panel);
        surface(confirm);
        lettering(text);
        lettering(actionTitle);
        lettering(demo.querySelector('.demo-return'));
        // Viewport-sized overlay lets fragments leave the card without clipping
        // against the demo's layout box or creating horizontal page overflow.
        canvas.width = Math.ceil(window.innerWidth * scale);
        canvas.height = Math.ceil(window.innerHeight * scale);
        context.setTransform(scale, 0, 0, scale, 0, 0);
        const cellSize = Math.max(5, Math.sqrt(bounds.width * bounds.height / 2200));
        return { texture, scale, width: bounds.width, height: bounds.height,
            x: bounds.left, y: bounds.top,
            columns: Math.max(2, Math.ceil(bounds.width / cellSize)),
            rows: Math.max(1, Math.ceil(bounds.height / cellSize)) };
    }

    // Same 500 ms, right-to-left breakup and upward drift as RecordPanel.animateWind.
    function drawWind(t) {
        if (!snapshot) return;
        const { texture, scale, width, height, x, y, columns, rows } = snapshot;
        const cellWidth = width / columns, cellHeight = height / rows;
        context.clearRect(0, 0, canvas.width / scale, canvas.height / scale);
        for (let row = 0; row < rows; row++) for (let column = 0; column < columns; column++) {
            const noise = Math.sin(column * 127.1 + row * 311.7) * 43758.5453;
            const flutterNoise = Math.sin(column * 269.5 + row * 183.3) * 24634.6345;
            const seed = noise - Math.floor(noise), flutter = flutterNoise - Math.floor(flutterNoise);
            const delay = (1 - column / (columns - 1)) * .54 + seed * .13;
            const progress = clamp((t - delay) / .33);
            if (progress >= 1) continue;
            const left = column * cellWidth, top = row * cellHeight;
            const drift = progress * .7 + progress * progress * .3;
            const dx = (34 + seed * 46) * drift;
            const dy = -(8 + flutter * 27) * progress
                + Math.sin(progress * Math.PI * 2 + seed * Math.PI * 2) * progress * 5;
            const size = 1 - smooth(progress) * .78;
            context.save();
            context.globalAlpha = 1 - smooth((progress - .18) / .82);
            context.translate(x + left + cellWidth / 2 + dx, y + top + cellHeight / 2 + dy);
            context.rotate((flutter - .5) * progress * 2.2);
            context.scale(size, size * (1 - Math.sin(progress * Math.PI) * flutter * .35));
            context.drawImage(texture, left * scale, top * scale, cellWidth * scale, cellHeight * scale,
                -cellWidth / 2, -cellHeight / 2, cellWidth, cellHeight);
            context.restore();
        }
    }

    function frame(now) {
        frameID = 0;
        if (lastFrame !== null) elapsed += now - lastFrame;
        lastFrame = now;
        if (state === 'idle' && elapsed >= 1000) setState('typing');
        else if (state === 'typing') {
            render();
            if (elapsed >= examples[selected].text.length * 48) setState('suggesting');
        } else if (state === 'suggesting' && elapsed >= 2200) setState('confirmed');
        else if (state === 'confirmed' && elapsed >= 180) {
            snapshot = capturePanel();
            setState('dissolving');
        } else if (state === 'dissolving' && elapsed >= 500) {
            snapshot = null;
            setState('completed');
        } else if (state === 'completed' && elapsed >= 1100) {
            selected = (selected + 1) % examples.length;
            setState('idle');
        }
        if (state === 'dissolving') drawWind(elapsed / 500);
        frameID = requestAnimationFrame(frame);
    }

    function syncPlayback() {
        cancelAnimationFrame(frameID);
        frameID = 0;
        lastFrame = null;
        const running = !paused && inView && !document.hidden && !motion.matches;
        demo.dataset.playback = running ? 'playing' : 'paused';
        if (running) frameID = requestAnimationFrame(frame);
    }

    function togglePause() {
        if (motion.matches) return;
        paused = !paused;
        status.textContent = paused ? 'Example paused. Press Space to resume.' : 'Example playing.';
        syncPlayback();
    }

    function confirmExample() {
        if (state !== 'suggesting') return;
        if (motion.matches) {
            selected = (selected + 1) % examples.length;
            render();
            status.textContent = `Next example: ${examples[selected].text}. ${examples[selected].action}.`;
        } else {
            paused = false;
            setState('confirmed');
            status.textContent = 'Example confirmed. The panel drifts away.';
            syncPlayback();
        }
    }

    confirm.addEventListener('click', event => { event.stopPropagation(); confirmExample(); });
    demo.addEventListener('click', togglePause);
    demo.addEventListener('keydown', event => {
        if (event.target === confirm || event.isComposing) return;
        if (event.key === ' ') { event.preventDefault(); togglePause(); }
        else if (event.key === 'Enter') { event.preventDefault(); confirmExample(); }
        else if (event.key === 'Escape' && !paused) togglePause();
    });
    motion.addEventListener('change', () => {
        snapshot = null;
        setState(motion.matches ? 'suggesting' : 'idle');
        syncPlayback();
    });
    document.addEventListener('visibilitychange', syncPlayback);
    window.addEventListener('pagehide', () => { cancelAnimationFrame(frameID); lastFrame = null; });
    window.addEventListener('pageshow', syncPlayback);
    new IntersectionObserver(entries => {
        inView = entries[0].isIntersecting;
        syncPlayback();
    }).observe(demo);
    function finishDisplacedEffect() {
        if (state !== 'dissolving') return;
        snapshot = null;
        setState('completed');
    }
    new ResizeObserver(finishDisplacedEffect).observe(demo);
    window.addEventListener('resize', finishDisplacedEffect);
    window.addEventListener('scroll', finishDisplacedEffect, { passive: true });
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
