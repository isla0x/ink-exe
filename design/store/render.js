const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const jobs = [];
  for (let s = 1; s <= 6; s++) {
    jobs.push(['iphone', '', 440, 956, 3, s, `iphone-0${s}`]);
    jobs.push(['iphone', '65', 428, 926, 3, s, `iphone65-0${s}`]);
    jobs.push(['ipad', '', 1032, 1376, 2, s, `ipad-0${s}`]);
  }
  jobs.push(['iphone', '', 440, 956, 3, 'pen', 'iap-review-1320x2868']);
  for (const [dev, size, w, h, dpr, shot, name] of jobs) {
    const p = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: dpr });
    await p.goto(`file://${__dirname}/shots.html?device=${dev}&size=${size}&shot=${shot}`);
    await p.evaluate(() => document.fonts.ready);
    await p.waitForTimeout(150);
    await p.screenshot({ path: `${__dirname}/out/${name}.png`, clip: { x: 0, y: 0, width: w, height: h } });
    await p.close();
  }
  await b.close();
})();
