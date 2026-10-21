import { useEffect, useMemo, useState } from 'react';
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import {
  AppleLogo,
  AndroidLogo,
  ArrowDownRight,
  ArrowRight,
  ArrowUpRight,
  Broadcast,
  Bug,
  CaretDown,
  Check,
  FlowArrow,
  GlobeHemisphereWest,
  GooglePlayLogo,
  LockKey,
  Moon,
  QrCode,
  SlidersHorizontal,
  Sparkle,
  Sun,
  WarningCircle,
} from '@phosphor-icons/react';
import { downloadLinks } from './download-links.js';

gsap.registerPlugin(ScrollTrigger);

const copy = {
  zh: {
    nav: { experience: '重新理解 Flow', features: '为什么是 Rivlen', download: '获取 Rivlen' },
    hero: {
      eyebrow: '移动端 Node-RED Flow 编辑器',
      title: '把 Flow，装进口袋。',
      body: '在熟悉的 Node-RED 逻辑里，拖动、编辑、部署，随时随地把自动化带在身边。',
      cta: '开始探索',
      note: '为真实运行环境而设计',
    },
    story: {
      eyebrow: '01 / 从复杂开始',
      title: '复杂的 Flow，\n也可以轻盈。',
      body: '桌面端的坐标和信息密度，不应该成为移动端的负担。Rivlen 会把原本的 Flow 保留下来，再为手指重新安排距离、层级和节奏。',
      small: '同一份逻辑，更自然的触摸。',
      tags: ['缩放坐标', '自动排开', '保留原始字段'],
    },
    ha: {
      eyebrow: '02 / 原生编辑',
      title: '不是 JSON 编辑器。',
      body: 'Home Assistant 节点里的服务、设备、实体和动作，都从你的 Node-RED 实例直接加载，按照网页版顺序呈现为可选择的表单。',
      labels: ['服务', '实体', '动作'],
      values: ['灯光 · 客厅', 'light.living_room', '打开'],
      note: '字段标题、顺序和本地化文字，跟着你的实例走。',
    },
    debug: {
      eyebrow: '03 / Debug 在场',
      title: '消息出现时，\n你会看见它。',
      body: 'Debug 节点会短暂发光，底部入口留下通知点。点击一下，就从画布跳到实时消息。',
      pulse: 'NEW MESSAGE',
      log: ['msg.payload  82.4', 'msg.topic    living_room', 'node         debug'],
      note: '收到消息 · 22:14:07',
    },
    gateway: {
      eyebrow: '04 / 私有连接',
      title: '你的 Flow，\n只经过你的网关。',
      body: '通过 Rivlen Gateway 连接已有 Node-RED 实例。手机负责编辑和观察，运行环境仍然留在你的局域网里。',
      points: ['扫码配对', '设备可撤销', '不运行第二套引擎'],
      cta: '了解连接方式',
    },
    download: {
      eyebrow: '05 / 带走 Rivlen',
      title: '把自动化，\n带到现场。',
      body: '选择你的平台。下载入口集中配置，链接更新后页面会自动同步。',
      unavailable: '链接待配置',
      play: 'Google Play',
      pgyer: '蒲公英测试版',
      ios: 'iOS 下载',
      foot: 'Rivlen · Flow editor for Node-RED',
    },
    language: 'English',
    theme: '切换深色模式',
  },
  en: {
    nav: { experience: 'Reframe the Flow', features: 'Why Rivlen', download: 'Get Rivlen' },
    hero: {
      eyebrow: 'Mobile Node-RED Flow editor',
      title: 'Flows in your hands.',
      body: 'Pan, edit, deploy, and debug the Node-RED flows you already run — wherever the work takes you.',
      cta: 'Explore the story',
      note: 'Built for real running systems',
    },
    story: {
      eyebrow: '01 / Start with complexity',
      title: 'Complex flows,\nmade lighter.',
      body: 'Desktop coordinates and information density should not become a mobile burden. Rivlen keeps the original Flow while rearranging space, hierarchy, and rhythm for touch.',
      small: 'The same logic, a more natural touch.',
      tags: ['Scaled coordinates', 'Auto spacing', 'Unknown fields kept'],
    },
    ha: {
      eyebrow: '02 / Native editing',
      title: 'Not a JSON editor.',
      body: 'Services, devices, entities, and actions in Home Assistant nodes load directly from your Node-RED instance and appear as ordered, selectable forms.',
      labels: ['Service', 'Entity', 'Action'],
      values: ['Light · Living room', 'light.living_room', 'Turn on'],
      note: 'Labels, order, and local language follow your instance.',
    },
    debug: {
      eyebrow: '03 / Debug, in the room',
      title: 'When a message arrives,\nyou see it.',
      body: 'The Debug node briefly lights up. A notification dot stays in the bottom bar. One tap opens the live message stream.',
      pulse: 'NEW MESSAGE',
      log: ['msg.payload  82.4', 'msg.topic    living_room', 'node         debug'],
      note: 'Message received · 22:14:07',
    },
    gateway: {
      eyebrow: '04 / Private connection',
      title: 'Your Flow,\nthrough your gateway.',
      body: 'Connect to an existing Node-RED instance through Rivlen Gateway. The phone edits and observes while the runtime stays inside your network.',
      points: ['Pair by QR', 'Revoke devices', 'No second engine'],
      cta: 'See how it connects',
    },
    download: {
      eyebrow: '05 / Take Rivlen with you',
      title: 'Bring automation\nto the field.',
      body: 'Choose your platform. Download links live in one place so the page stays easy to update.',
      unavailable: 'Link to be configured',
      play: 'Google Play',
      pgyer: 'Pgyer beta',
      ios: 'iOS download',
      foot: 'Rivlen · Flow editor for Node-RED',
    },
    language: '中文',
    theme: 'Toggle dark mode',
  },
};

function App() {
  const [language, setLanguage] = useState('zh');
  const [darkMode, setDarkMode] = useState(false);
  const t = useMemo(() => copy[language], [language]);

  useEffect(() => {
    document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
    document.title = language === 'zh' ? 'Rivlen｜把 Flow，装进口袋' : 'Rivlen | Flows in your hands';
    requestAnimationFrame(() => ScrollTrigger.refresh());
  }, [language]);

  useEffect(() => {
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduceMotion) return undefined;
    const context = gsap.context(() => {
      gsap.from('.nav-shell', { y: -24, autoAlpha: 0, duration: 0.8, ease: 'power3.out' });
      gsap.from('.hero-copy > *', { y: 42, autoAlpha: 0, duration: 1, stagger: 0.08, delay: 0.2, ease: 'power3.out' });
      gsap.from('.hero-art', { x: 60, y: 24, rotate: 2, autoAlpha: 0, duration: 1.2, delay: 0.35, ease: 'power3.out' });
      gsap.to('.hero-art', { yPercent: -10, rotate: -1, ease: 'none', scrollTrigger: { trigger: '.hero', start: 'top top', end: 'bottom top', scrub: true } });
      gsap.utils.toArray('.reveal').forEach((element) => gsap.from(element, { y: 36, autoAlpha: 0, duration: 0.9, ease: 'power3.out', scrollTrigger: { trigger: element, start: 'top 82%', once: true } }));
      gsap.to('.story-line-progress', { height: '100%', ease: 'none', scrollTrigger: { trigger: '.story-track', start: 'top 18%', end: 'bottom 82%', scrub: true } });
      gsap.to('.story-image', { scale: 1.04, yPercent: -4, ease: 'none', scrollTrigger: { trigger: '.story-track', start: 'top bottom', end: 'bottom top', scrub: true } });
      gsap.to('.debug-atmosphere', { scale: 1.08, xPercent: 3, ease: 'none', scrollTrigger: { trigger: '.debug-section', start: 'top bottom', end: 'bottom top', scrub: true } });
      gsap.from('.debug-pulse', { boxShadow: '0 0 0 0 rgba(234, 114, 95, 0)', scale: 0.92, repeat: -1, yoyo: true, duration: 1.4, ease: 'sine.inOut', scrollTrigger: { trigger: '.debug-section', start: 'top 64%', end: 'bottom 34%', toggleActions: 'play pause resume pause' } });
      gsap.to('.footer-mark', { rotate: 8, ease: 'none', scrollTrigger: { trigger: '.download-section', start: 'top bottom', end: 'bottom top', scrub: true } });
    });
    return () => context.revert();
  }, []);

  const scrollTo = (id) => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });

  return (
    <div className={`site ${darkMode ? 'is-dark' : ''}`}>
      <header className="nav-shell">
        <a className="brand" href="#top" aria-label="Rivlen home"><img src="/assets/rivlen-mark.svg" alt="" /><span>Rivlen</span></a>
        <nav className="nav-links" aria-label="Primary navigation">
          <button type="button" onClick={() => scrollTo('experience')}>{t.nav.experience}</button>
          <button type="button" onClick={() => scrollTo('features')}>{t.nav.features}</button>
          <button type="button" onClick={() => scrollTo('download')}>{t.nav.download}</button>
        </nav>
        <div className="nav-tools">
          <button className="icon-button" type="button" onClick={() => setDarkMode((value) => !value)} aria-label={t.theme}>{darkMode ? <Sun size={18} /> : <Moon size={18} />}</button>
          <button className="language-toggle" type="button" aria-label={t.language} onClick={() => setLanguage(language === 'zh' ? 'en' : 'zh')}><GlobeHemisphereWest size={17} /><span>{t.language}</span></button>
        </div>
      </header>

      <main id="top">
        <section className="hero section-shell">
          <div className="hero-copy"><div className="eyebrow"><span className="eyebrow-dot" />{t.hero.eyebrow}</div><h1>{t.hero.title}</h1><p className="hero-body">{t.hero.body}</p><div className="hero-actions"><button className="button button-primary" type="button" onClick={() => scrollTo('experience')}>{t.hero.cta}<ArrowRight size={18} weight="bold" /></button><span className="hero-note"><Sparkle size={15} weight="fill" />{t.hero.note}</span></div></div>
          <div className="hero-art" aria-label="Rivlen flow editor preview"><img src="/assets/flow-hero.png" alt="A Node-RED flow arranged on a mobile canvas" /><div className="hero-art-caption"><span>Rivlen / 01</span><span>Flow editor</span></div></div>
          <div className="hero-scroll"><span>Scroll to move through the flow</span><ArrowDownRight size={16} /></div>
        </section>

        <section className="marquee-band" aria-label="Rivlen principles"><div className="marquee-track"><span>Pan</span><i /><span>Connect</span><i /><span>Edit</span><i /><span>Deploy</span><i /><span>Debug</span><i /><span>Pan</span><i /><span>Connect</span><i /></div></section>

        <section id="experience" className="story-track section-shell"><div className="story-intro reveal"><div className="eyebrow"><span className="eyebrow-dot" />{t.story.eyebrow}</div><h2>{t.story.title.split('\n').map((line) => <span key={line}>{line}<br /></span>)}</h2><p>{t.story.body}</p><div className="story-small"><FlowArrow size={18} />{t.story.small}</div><div className="tag-row">{t.story.tags.map((tag) => <span key={tag}>{tag}</span>)}</div></div><div className="story-stage"><div className="story-line" aria-hidden="true"><span className="story-line-progress" /></div><div className="story-image reveal"><img src="/assets/rivlen-app-preview.png" alt="Rivlen connection screen running in an iOS simulator" /><div className="image-label"><span>01</span><span>{language === 'zh' ? '连接你的实例' : 'Connect your instance'}</span></div></div></div></section>

        <section id="features" className="ha-section section-shell"><div className="ha-copy reveal"><div className="eyebrow"><span className="eyebrow-dot" />{t.ha.eyebrow}</div><h2>{t.ha.title}</h2><p>{t.ha.body}</p><div className="ha-note"><Check size={16} weight="bold" />{t.ha.note}</div></div><div className="form-stage reveal"><div className="form-window-top"><span>Home Assistant</span><span className="window-dots"><i /><i /><i /></span></div><div className="form-heading"><span>{language === 'zh' ? '编辑节点' : 'Edit node'}</span><SlidersHorizontal size={18} /></div><div className="form-list">{t.ha.labels.map((label, index) => <label key={label}><span>{label}</span><div className="select-field"><span>{t.ha.values[index]}</span><CaretDown size={15} /></div></label>)}</div><div className="form-foot"><span className="form-status" />{language === 'zh' ? '从实例加载' : 'Loaded from instance'}<ArrowUpRight size={15} /></div></div></section>

        <section className="debug-section"><img className="debug-atmosphere" src="/assets/debug-atmosphere.png" alt="" aria-hidden="true" /><div className="debug-inner section-shell"><div className="debug-copy reveal"><div className="eyebrow eyebrow-light"><span className="eyebrow-dot" />{t.debug.eyebrow}</div><h2>{t.debug.title.split('\n').map((line) => <span key={line}>{line}<br /></span>)}</h2><p>{t.debug.body}</p><div className="debug-message"><span className="debug-pulse" /><span>{t.debug.pulse}</span><ArrowUpRight size={16} /></div></div><div className="debug-console reveal"><div className="console-header"><span><Bug size={18} weight="fill" />Debug</span><span className="console-live"><i />LIVE</span></div><div className="console-lines">{t.debug.log.map((line) => <code key={line}>{line}</code>)}</div><div className="console-foot"><Broadcast size={16} />{t.debug.note}</div></div></div></section>

        <section className="gateway-section section-shell"><div className="gateway-art reveal"><div className="gateway-ring ring-one" /><div className="gateway-ring ring-two" /><div className="gateway-core"><QrCode size={54} weight="thin" /><span>Rivlen Gateway</span></div><div className="gateway-node node-a"><span />Node-RED</div><div className="gateway-node node-b"><LockKey size={15} />Private</div><div className="gateway-node node-c"><span />Phone</div></div><div className="gateway-copy reveal"><div className="eyebrow"><span className="eyebrow-dot" />{t.gateway.eyebrow}</div><h2>{t.gateway.title.split('\n').map((line) => <span key={line}>{line}<br /></span>)}</h2><p>{t.gateway.body}</p><ul>{t.gateway.points.map((point) => <li key={point}><Check size={16} weight="bold" />{point}</li>)}</ul><button className="text-link" type="button" onClick={() => scrollTo('download')}>{t.gateway.cta}<ArrowRight size={17} /></button></div></section>

        <section id="download" className="download-section section-shell"><div className="download-copy reveal"><div className="eyebrow"><span className="eyebrow-dot" />{t.download.eyebrow}</div><h2>{t.download.title.split('\n').map((line) => <span key={line}>{line}<br /></span>)}</h2><p>{t.download.body}</p></div><div className="download-panel reveal"><DownloadButton icon={<GooglePlayLogo size={23} weight="fill" />} label={t.download.play} href={downloadLinks.play} unavailable={t.download.unavailable} /><DownloadButton icon={<AndroidLogo size={23} weight="fill" />} label={t.download.pgyer} href={downloadLinks.pgyer} unavailable={t.download.unavailable} /><DownloadButton icon={<AppleLogo size={23} weight="fill" />} label={t.download.ios} href={downloadLinks.ios} unavailable={t.download.unavailable} /></div><div className="download-foot"><span>{t.download.foot}</span><img className="footer-mark" src="/assets/rivlen-mark.svg" alt="" /></div></section>
      </main>
    </div>
  );
}

function DownloadButton({ icon, label, href, unavailable }) {
  if (!href) return <button className="download-button is-disabled" type="button" title={unavailable}><span className="download-icon">{icon}</span><span className="download-label"><strong>{label}</strong><small>{unavailable}</small></span><WarningCircle size={18} /></button>;
  return <a className="download-button" href={href} target="_blank" rel="noreferrer"><span className="download-icon">{icon}</span><span className="download-label"><strong>{label}</strong><small>Download</small></span><ArrowUpRight size={18} /></a>;
}

export default App;
