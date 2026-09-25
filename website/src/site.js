'use strict';
const panel = document.querySelector('.panel-scene');
const panelImage = document.querySelector('#launcher-image');
const appearanceButtons = document.querySelectorAll('[data-theme]');
for (const button of appearanceButtons) {
    button.addEventListener('click', () => {
        const theme = button.dataset.theme;
        panel.dataset.appearance = theme;
        panelImage.src = `/assets/launcher-${theme}.png`;
        for (const option of appearanceButtons) {
            option.setAttribute('aria-pressed', String(option === button));
        }
    });
}
const copyButton = document.querySelector('#copy-checksum');
copyButton?.addEventListener('click', async () => {
    const status = document.querySelector('#copy-status');
    try {
        await navigator.clipboard.writeText(document.querySelector('#checksum').textContent.trim());
        status.textContent = '已复制';
    } catch {
        status.textContent = '无法自动复制，请选择上方校验值复制。';
    }
});
