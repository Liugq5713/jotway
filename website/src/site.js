'use strict';

const demo = document.querySelector('#product-demo');
if (demo) {
    const examples = {
        notes: {
            text: 'Save to notes: a quiet weekend in Kyoto',
            action: 'Save to Notes', destination: 'Apple Notes',
        },
        reminders: {
            text: 'Remind me to send the design draft',
            action: 'Save to Reminders', destination: 'Apple Reminders',
        },
        calendar: {
            text: 'Add to calendar: design discussion',
            action: 'Save to Calendar', destination: 'Apple Calendar',
        },
        chrome: {
            text: 'Google search macOS keyboard shortcuts',
            action: 'Google Search', destination: 'Chrome',
        },
    };
    const sequence = ['idle', 'typing', 'suggesting', 'confirmed', 'completed'];
    const delays = { idle: 1000, typing: 48, suggesting: 3200, confirmed: 950 };
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const text = demo.querySelector('#demo-text');
    const draft = demo.querySelector('#demo-draft');
    const placeholder = demo.querySelector('#demo-placeholder');
    const confirm = demo.querySelector('#demo-confirm');
    const confirmation = demo.querySelector('#demo-confirmation');
    const actionTitle = demo.querySelector('#demo-action-title');
    const status = demo.querySelector('#demo-status');
    const counter = demo.querySelector('#demo-counter');
    const outcome = demo.querySelector('#demo-outcome');
    const outcomeTitle = demo.querySelector('#demo-outcome-title');
    const outcomeText = demo.querySelector('#demo-outcome-text');
    const play = demo.querySelector('#demo-play');
    const playLabel = demo.querySelector('#demo-play-label');
    const playIcon = demo.querySelector('#demo-play-icon');
    const replay = demo.querySelector('#demo-replay');
    const chips = demo.querySelectorAll('[data-action]');
    const steps = demo.querySelectorAll('[data-step]');
    const motionNote = demo.querySelector('#demo-motion-note');
    let selected = 'notes';
    let state = 'idle';
    let characters = 0;
    let paused = document.hidden;
    let timer = null;
    let deadline = 0;
    let remaining = null;

    function cancelTimer() {
        window.clearTimeout(timer);
        timer = null;
    }

    function render() {
        const example = examples[selected];
        const completed = state === 'completed';
        const restoreFocus = (state === 'confirmed' || completed)
            && demo.querySelector('#demo-panel').contains(document.activeElement);
        const running = !paused && !completed && !motion.matches;
        demo.dataset.state = state;
        demo.dataset.playback = running ? 'playing' : 'paused';
        demo.dataset.action = selected;
        text.textContent = state === 'idle' || completed ? '' : example.text.slice(0, characters);
        placeholder.hidden = state !== 'idle' && !completed;
        draft.tabIndex = completed ? -1 : 0;
        draft.setAttribute('aria-hidden', String(completed));
        actionTitle.textContent = example.action;
        confirm.disabled = state !== 'suggesting';
        confirmation.textContent = state === 'confirmed' ? 'Example: Enter ↵' : '';
        outcome.hidden = !completed;
        outcomeTitle.textContent = `Handed to ${example.destination}`;
        outcomeText.textContent = example.text;
        counter.textContent = `0${sequence.indexOf(state) + 1} / 05`;
        playLabel.textContent = running ? 'Pause' : 'Play';
        playIcon.textContent = running ? 'Ⅱ' : '▶';
        play.setAttribute('aria-label', running ? 'Pause demo' : 'Play demo');
        motionNote.hidden = !motion.matches;
        for (const chip of chips) {
            chip.setAttribute('aria-pressed', String(chip.dataset.action === selected));
        }
        for (const step of steps) {
            if (step.dataset.step === state) step.setAttribute('aria-current', 'step');
            else step.removeAttribute('aria-current');
            step.classList.toggle('is-past', sequence.indexOf(step.dataset.step) < sequence.indexOf(state));
        }
        const messages = {
            idle: 'Open the quick record panel with your shortcut.',
            typing: 'Write a thought. No need to organize it first.',
            suggesting: `Suggested: ${example.action}. Next: an example Enter press.`,
            confirmed: `Enter confirmed ${example.action}. Now the handoff can happen.`,
            completed: `Demo complete. Handed to ${example.destination}; the panel is now clear.`,
        };
        const prefix = paused && !completed ? 'Paused. ' : '';
        const message = prefix + messages[state];
        // Announce stages, not every typed character. Keep focus on a usable control
        // when confirmation disables or hides the focused part of the panel.
        if (status.textContent !== message) status.textContent = message;
        if (restoreFocus) replay.focus({ preventScroll: true });
    }

    function schedule(delay = delays[state]) {
        cancelTimer();
        if (paused || motion.matches || state === 'completed') return;
        deadline = performance.now() + delay;
        timer = window.setTimeout(() => {
            timer = null;
            remaining = null;
            advance();
        }, delay);
    }

    function advance() {
        if (state === 'typing' && characters < examples[selected].text.length) {
            characters += 1;
        } else {
            state = sequence[Math.min(sequence.indexOf(state) + 1, sequence.length - 1)];
        }
        render();
        schedule();
    }

    function start(keepPaused = false) {
        cancelTimer();
        remaining = null;
        paused = keepPaused || document.hidden;
        state = motion.matches ? 'completed' : 'idle';
        characters = motion.matches ? examples[selected].text.length : 0;
        render();
        schedule();
    }

    function pause() {
        if (timer !== null) remaining = Math.max(0, deadline - performance.now());
        cancelTimer();
        paused = true;
        render();
    }

    function confirmExample() {
        if (state !== 'suggesting') return;
        cancelTimer();
        remaining = null;
        paused = false;
        state = motion.matches ? 'completed' : 'confirmed';
        render();
        schedule();
    }

    play.addEventListener('click', () => {
        if (state === 'completed') start();
        else if (!paused) pause();
        else {
            paused = false;
            render();
            schedule(remaining ?? delays[state]);
            remaining = null;
        }
    });
    replay.addEventListener('click', () => start());
    for (const chip of chips) {
        chip.addEventListener('click', () => {
            selected = chip.dataset.action;
            start(paused);
        });
    }
    confirm.addEventListener('click', confirmExample);
    draft.addEventListener('keydown', event => {
        if (event.key === 'Enter' && !event.isComposing && !event.shiftKey) {
            event.preventDefault();
            confirmExample();
        }
    });
    motion.addEventListener('change', () => start(paused));
    document.addEventListener('visibilitychange', () => {
        if (document.hidden) pause();
    });
    window.addEventListener('pagehide', pause);
    demo.querySelector('#demo-controls').hidden = false;
    start();
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
