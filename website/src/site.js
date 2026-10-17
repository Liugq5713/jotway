const demo = document.querySelector('#product-demo');
if (demo) {
    const scenes = [...demo.querySelectorAll('.demo-scene')];
    const play = document.querySelector('#demo-play');
    const status = document.querySelector('#demo-status');
    const motion = matchMedia('(prefers-reduced-motion: reduce)');
    const duration = 6;
    let elapsed = duration, paused = true, inView = true, pageActive = true;
    let frameID = 0, lastFrame = null;
    function render() {
        for (const scene of scenes) {
            scene.querySelector('.demo-preview').hidden = elapsed < 2;
            scene.querySelector('.demo-result').hidden = elapsed < 4;
        }
        play.textContent = motion.matches ? 'Static example' : paused ? (elapsed >= duration ? 'Play example' : 'Resume example') : 'Pause example';
        play.disabled = motion.matches;
    }
    function pause() {
        paused = true;
        syncPlayback();
        render();
    }
    function frame(now) {
        frameID = 0;
        if (lastFrame !== null) elapsed = Math.min(duration, elapsed + (now - lastFrame) / 1000);
        lastFrame = now;
        if (elapsed >= duration) {
            paused = true;
            status.textContent = 'Illustrative result after confirmation. Nothing was saved by this page.';
        }
        render();
        if (!paused) frameID = requestAnimationFrame(frame);
        else syncPlayback();
    }
    function syncPlayback() {
        cancelAnimationFrame(frameID);
        frameID = 0;
        lastFrame = null;
        const running = !paused && inView && pageActive && !document.hidden && !motion.matches;
        demo.dataset.playback = running ? 'playing' : 'paused';
        if (running) frameID = requestAnimationFrame(frame);
    }
    function start() {
        if (motion.matches) return;
        if (elapsed >= duration) elapsed = 0;
        paused = false;
        status.textContent = 'Example playing. Use Pause example or Escape to pause.';
        render();
        syncPlayback();
    }
    play.addEventListener('click', () => {
        if (paused) start();
        else { pause(); status.textContent = 'Example paused.'; }
    });
    demo.addEventListener('keydown', event => {
        if (event.key === 'Escape') { pause(); status.textContent = 'Example paused.'; }
    });
    motion.addEventListener('change', () => { elapsed = duration; pause(); });
    document.addEventListener('visibilitychange', () => { if (document.hidden) pause(); });
    window.addEventListener('pagehide', () => { pageActive = false; pause(); });
    window.addEventListener('pageshow', () => { pageActive = true; syncPlayback(); });
    new IntersectionObserver(entries => {
        inView = entries[0].isIntersecting;
        if (!inView) pause();
    }, { threshold: .1 }).observe(demo);
    window.jotwayDemo = Object.freeze({
        duration,
        seek(seconds) {
            if (!Number.isFinite(seconds)) return;
            elapsed = motion.matches ? duration : Math.max(0, Math.min(duration, seconds));
            pause();
        },
        play: start,
        pause,
    });
    document.querySelector('#demo-controls').hidden = false;
    demo.dataset.ready = 'true';
    render();
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
