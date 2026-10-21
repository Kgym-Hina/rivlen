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
  Lightbulb,
  Fan,
  Thermometer,
  Moon,
  QrCode,
  SlidersHorizontal,
  Sparkle,
  Sun,
  WarningCircle,
} from '@phosphor-icons/react';
import { downloadLinks } from './download-links.js';

gsap.registerPlugin(ScrollTrigger);
// Mobile browser chrome must not rebuild scroll distances during a gesture.
ScrollTrigger.config({ ignoreMobileResize: true });

const copy = {
  zh: {
    nav: { experience: '重新理解 Flow', features: '为什么是 Rivlen', download: '获取 Rivlen' },
    hero: {
      eyebrow: '移动端 Node-RED Flow 编辑器',
      title: '把 Flow，装进口袋。',
      body: '拖动节点，连接逻辑，随时调试。',
      cta: '开始探索',
      note: '为真实 Flow 设计',
    },
    nodes: {
      eyebrow: '01 / 节点就是语言',
      title: '连起来，就发生。',
      body: 'Inject、Function、Home Assistant、Debug：把逻辑放回画布。',
      labels: ['Inject', 'Function', 'Home Assistant', 'Debug'],
      captions: ['触发', '处理', '设备动作', '实时消息'],
      steps: ['连接', '传递', '灯亮了'],
    },
    story: {
      eyebrow: '02 / 从复杂开始',
      title: '复杂 Flow，\n轻一点。',
      body: '为手指，留出空间。',
      small: '逻辑如旧，触摸更轻。',
      tags: ['缩放坐标', '自动排开', '字段保留'],
    },
    ha: {
      eyebrow: '03 / 原生编辑',
      title: '让家，回应。',
      body: '选设备，定动作。',
      labels: ['服务', '实体', '动作'],
      values: ['灯光 · 客厅', 'light.living_room', '打开'],
      note: '来自你的实例',
    },
    debug: {
      eyebrow: '04 / Debug 在场',
      title: '回应，\n即刻看见。',
      body: '每条消息，都有回响。',
      pulse: 'NEW MESSAGE',
      log: ['msg.payload  on', 'msg.topic    living_room', 'node         debug'],
      note: '收到消息 · 22:14:07',
    },
    gateway: {
      eyebrow: '05 / 私有连接',
      title: '连接，\n由你掌控。',
      body: '编辑在手边，运行在本地。',
      points: ['扫码配对', '可撤销设备', '不重复运行'],
      cta: '了解连接方式',
    },
    download: {
      eyebrow: '06 / 带走 Rivlen',
      title: '把自动化，\n带到现场。',
      body: '选择平台，带走你的 Flow。',
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
      body: 'Drag nodes, connect logic, debug anywhere.',
      cta: 'Explore the story',
      note: 'Built for real Flows',
    },
    nodes: {
      eyebrow: '01 / Nodes are the language',
      title: 'Connect. Make it happen.',
      body: 'Inject, Function, Home Assistant, and Debug stay visible on the canvas.',
      labels: ['Inject', 'Function', 'Home Assistant', 'Debug'],
      captions: ['Trigger', 'Transform', 'Device action', 'Live message'],
      steps: ['Connect', 'Send', 'Lights on'],
    },
    story: {
      eyebrow: '02 / Start with complexity',
      title: 'Complex flows,\nmade light.',
      body: 'Room for your fingers.',
      small: 'Familiar logic. Lighter touch.',
      tags: ['Scaled coordinates', 'Auto spacing', 'Fields kept'],
    },
    ha: {
      eyebrow: '03 / Native editing',
      title: 'Bring it to life.',
      body: 'Choose a device. Set an action.',
      labels: ['Service', 'Entity', 'Action'],
      values: ['Light · Living room', 'light.living_room', 'Turn on'],
      note: 'From your instance',
    },
    debug: {
      eyebrow: '04 / Debug, in the room',
      title: 'See every\nresponse.',
      body: 'Every message, in sight.',
      pulse: 'NEW MESSAGE',
      log: ['msg.payload  on', 'msg.topic    living_room', 'node         debug'],
      note: 'Message received · 22:14:07',
    },
    gateway: {
      eyebrow: '05 / Private connection',
      title: 'Your connection.\nYour control.',
      body: 'Edit anywhere. Run locally.',
      points: ['Pair by QR', 'Revoke devices', 'No duplicate runtime'],
      cta: 'See how it connects',
    },
    download: {
      eyebrow: '06 / Take Rivlen with you',
      title: 'Bring automation\nto the field.',
      body: 'Choose a platform. Take your Flow with you.',
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
  const nodeGlyphs = [FlowArrow, SlidersHorizontal, Broadcast, Bug];

  useEffect(() => {
    document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
    document.title = language === 'zh' ? 'Rivlen｜把 Flow，装进口袋' : 'Rivlen | Flows in your hands';
    requestAnimationFrame(() => ScrollTrigger.refresh());
  }, [language]);

  useEffect(() => {
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduceMotion) {
      const drawStaticWires = () => {
        const rail = document.querySelector('.node-rail').getBoundingClientRect();
        const cards = document.querySelectorAll('.node-card');
        document.querySelectorAll('.flow-wire').forEach((path, index) => {
          const from = cards[index].querySelector('.node-port-out').getBoundingClientRect();
          const to = cards[index + 1].querySelector('.node-port-in').getBoundingClientRect();
          const sx = from.left + from.width / 2 - rail.left;
          const sy = from.top + from.height / 2 - rail.top;
          const ex = to.left + to.width / 2 - rail.left;
          const ey = to.top + to.height / 2 - rail.top;
          const d = `M ${sx} ${sy} C ${sx + 20} ${sy} ${ex - 20} ${ey} ${ex} ${ey}`;
          path.setAttribute('d', d);
          path.previousElementSibling.setAttribute('d', d);
        });
      };
      drawStaticWires();
      window.addEventListener('resize', drawStaticWires);
      return () => window.removeEventListener('resize', drawStaticWires);
    }
    const context = gsap.context(() => {
      gsap.from('.nav-shell', { y: -24, autoAlpha: 0, duration: 0.8, ease: 'power3.out' });
      gsap.from('.hero-copy > *', { y: 42, autoAlpha: 0, duration: 1, stagger: 0.08, delay: 0.2, ease: 'power3.out' });
      gsap.from('.hero-art', { x: 60, y: 24, rotate: 2, autoAlpha: 0, duration: 1.2, delay: 0.35, ease: 'power3.out' });
      gsap.to('.hero-art', { yPercent: -10, rotate: -1, ease: 'none', scrollTrigger: { trigger: '.hero', start: 'top top', end: 'bottom top', scrub: true } });
      gsap.utils.toArray('.reveal').forEach((element) => gsap.from(element, { y: 36, autoAlpha: 0, duration: 0.9, ease: 'power3.out', scrollTrigger: { trigger: element, start: 'top 82%', once: true } }));
      // Native sticky layout keeps the document geometry identical at both boundaries.
      const chapterDistance = (selector) => {
        const chapter = document.querySelector(selector);
        return Math.max(1, chapter.offsetHeight - chapter.firstElementChild.offsetHeight);
      };
      const rail = document.querySelector('.node-rail');
      const cards = gsap.utils.toArray('.node-card');
      const paths = gsap.utils.toArray('.flow-wire');
      const packets = gsap.utils.toArray('.flow-packet');
      const measureWires = () => {
        const bounds = rail.getBoundingClientRect();
        paths.forEach((path, index) => {
          const from = cards[index].querySelector('.node-port-out').getBoundingClientRect();
          const to = cards[index + 1].querySelector('.node-port-in').getBoundingClientRect();
          const sx = from.left + from.width / 2 - bounds.left;
          const sy = from.top + from.height / 2 - bounds.top;
          const ex = to.left + to.width / 2 - bounds.left;
          const ey = to.top + to.height / 2 - bounds.top;
          const middle = (sy + ey) / 2;
          const bend = window.innerWidth <= 520 ? 20 : 40;
          const d = index === 1
            ? `M ${sx} ${sy} C ${sx + bend} ${sy} ${sx + bend} ${middle} ${sx} ${middle} L ${ex} ${middle} C ${ex - bend} ${middle} ${ex - bend} ${ey} ${ex} ${ey}`
            : `M ${sx} ${sy} C ${sx + 45} ${sy} ${ex - 45} ${ey} ${ex} ${ey}`;
          path.setAttribute('d', d);
          path.previousElementSibling.setAttribute('d', d);
        });
      };
      measureWires();
      gsap.set(paths, { strokeDasharray: 1, strokeDashoffset: 1 });
      gsap.set('.flow-caption', { autoAlpha: 0, y: 10 });
      gsap.set('.flow-caption-0', { autoAlpha: 1, y: 0 });
      gsap.set('.flow-packet, .flow-result, .node-notification', { autoAlpha: 0 });
      const flow = gsap.timeline({ scrollTrigger: {
        trigger: '.node-chapter', start: 'top top', end: () => `+=${chapterDistance('.node-chapter')}`,
        scrub: 0.65, invalidateOnRefresh: true,
        onRefreshInit: measureWires,
      } });
      flow.from(cards, { opacity: 0.35, stagger: 0.1, duration: 0.6 })
        .to(paths, { strokeDashoffset: 0, stagger: 0.45, duration: 0.65, ease: 'none' }, 0.5)
        .to('.flow-caption-0', { autoAlpha: 0, y: -10, duration: 0.2 }, 2.1)
        .to('.flow-caption-1', { autoAlpha: 1, y: 0, duration: 0.2 }, 2.3);
      paths.forEach((path, index) => {
        const travel = { progress: 0 };
        const packet = packets[index];
        flow.to(packet, { autoAlpha: 1, duration: 0.05 }, 2.5 + index * 0.5)
          .to(travel, { progress: 1, duration: 0.5, ease: 'none', onUpdate: () => {
            const point = path.getPointAtLength(path.getTotalLength() * travel.progress);
            packet.setAttribute('cx', point.x);
            packet.setAttribute('cy', point.y);
          } }, 2.5 + index * 0.5)
          .to(packet, { autoAlpha: 0, duration: 0.05 }, 3 + index * 0.5)
          .to(cards[index + 1], { borderColor: '#ea725f', boxShadow: '0 0 35px rgba(234,114,95,.25)', duration: 0.2 }, 3 + index * 0.5)
          .to(cards[index + 1], { borderColor: '', boxShadow: '', duration: 0.35 }, 3.2 + index * 0.5);
      });
      flow.to('.flow-device-glow', { opacity: 1, scale: 1, duration: 0.4 }, 3.5)
        .to('.flow-device-icon', { color: '#d99b2e', duration: 0.3 }, 3.5);
      flow.to('.flow-caption-1', { autoAlpha: 0, y: -10, duration: 0.2 }, 4.1)
        .to('.flow-caption-2', { autoAlpha: 1, y: 0, duration: 0.2 }, 4.3)
        .to('.node-notification', { autoAlpha: 1, scale: 1.15, duration: 0.2 }, 4.1)
        .fromTo('.flow-result', { y: 16 }, { y: 0, autoAlpha: 1, duration: 0.4 }, 4.3)
        .to({}, { duration: 0.6 });
      gsap.to('.flow-progress span', { scaleX: 1, ease: 'none', scrollTrigger: {
        trigger: '.node-chapter', start: 'top top', end: () => `+=${chapterDistance('.node-chapter')}`, scrub: true,
      } });
      gsap.set('.flow-device-glow', { opacity: 0, scale: 0.65 });
      gsap.set('.room-response', { '--light-level': 0 });
      const form = gsap.timeline({ scrollTrigger: {
        trigger: '.ha-chapter', start: 'top top', end: () => `+=${chapterDistance('.ha-chapter')}`,
        scrub: 0.6,
      } });
      form.from('.form-stage', { rotate: 4, scale: 0.92, duration: 0.7 })
        .from('.form-list label', { x: 35, opacity: 0, stagger: 0.4, duration: 0.5 }, 0.25)
        .from('.form-foot', { opacity: 0, y: 10, duration: 0.3 })
        .to('.select-field', { borderColor: '#ea725f', stagger: 0.16, duration: 0.2 })
        .to('.select-field', { borderColor: '', duration: 0.3 })
        .to('.room-response', { '--light-level': 1, duration: 0.7 }, '>-0.2')
        .to('.room-bulb', { color: '#d99b2e', duration: 0.5 }, '<')
        .fromTo('.room-dimmer span', { scaleX: 0 }, { scaleX: 0.82, duration: 0.7 }, '<')
        .fromTo('.room-fan svg', { rotation: 0 }, { rotation: 540, duration: 1.3, ease: 'power1.inOut' }, '<')
        .fromTo('.room-temperature-value', { textContent: 26 }, { textContent: 22, snap: { textContent: 1 }, duration: 1.1 }, '<')
        .to({}, { duration: 0.3 });
      gsap.timeline({ scrollTrigger: { trigger: '.debug-chapter', start: 'top top',
        end: () => `+=${chapterDistance('.debug-chapter')}`, scrub: 0.6 } })
        .from('.debug-console', { y: 50, rotateX: 12, scale: 0.94, duration: 0.6 })
        .from('.console-lines code', { y: 20, opacity: 0, stagger: 0.4, duration: 0.5 }, 0.3)
        .from('.console-foot', { opacity: 0, duration: 0.3 })
        .from('.debug-message', { opacity: 0, scale: 0.9, duration: 0.3 });
      gsap.from('.gateway-node', { scale: 0.6, opacity: 0, stagger: 0.2, ease: 'none', scrollTrigger: {
        trigger: '.gateway-section', start: 'top 75%', end: 'center center', scrub: 0.6,
      } });
      gsap.from('.gateway-ring', { scale: 0.5, opacity: 0, stagger: 0.2, scrollTrigger: {
        trigger: '.gateway-section', start: 'top 80%', end: 'center center', scrub: 0.7,
      } });
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
          <div className="hero-art" aria-label="Rivlen flow editor preview"><img src="/assets/flow-hero.png" width="900" height="1024" alt="A Node-RED flow arranged on a mobile canvas" /><div className="hero-art-caption"><span>Rivlen / 01</span><span>Flow editor</span></div></div>
          <div className="hero-scroll"><span>Scroll to move through the flow</span><ArrowDownRight size={16} /></div>
        </section>

        <section className="marquee-band" aria-label="Rivlen principles"><div className="marquee-track"><span>Pan</span><i /><span>Connect</span><i /><span>Edit</span><i /><span>Deploy</span><i /><span>Debug</span><i /><span>Pan</span><i /><span>Connect</span><i /></div></section>

        <div className="scroll-chapter node-chapter"><section className="node-showcase section-shell"><div className="node-showcase-copy"><div className="eyebrow"><span className="eyebrow-dot" />{t.nodes.eyebrow}</div><h2>{t.nodes.title}</h2><div className="flow-captions">{t.nodes.steps.map((step, index) => <p className={`flow-caption flow-caption-${index}`} key={step}>{step}</p>)}</div><div className="flow-progress" aria-hidden="true"><span /></div></div><div className="node-rail" aria-label={language === 'zh' ? 'Node-RED 节点连接动画' : 'Node-RED connection animation'}><svg className="flow-wires" aria-hidden="true">{[0, 1, 2].map((index) => <g key={index}><path className="flow-wire-track" /><path className={`flow-wire flow-wire-${index}`} pathLength="1" /><circle className={`flow-packet flow-packet-${index}`} r="5" /></g>)}</svg>{t.nodes.labels.map((label, index) => { const Icon = nodeGlyphs[index]; return <div className={`node-card node-card-${index}`} key={label}>{index !== 0 && <span className="node-port node-port-in" aria-hidden="true" />}<span className="node-card-icon"><Icon size={19} weight="bold" /></span><span className="node-card-copy"><strong>{label}</strong><small>{t.nodes.captions[index]}</small></span>{index !== 3 && <span className="node-port node-port-out" aria-hidden="true" />}{index === 3 && <span className="node-notification" aria-hidden="true" />}</div>; })}<div className="flow-device" aria-hidden="true"><span className="flow-device-glow" /><Lightbulb className="flow-device-icon" size={29} weight="fill" /><code>light.turn_on</code></div><div className="flow-result"><span className="form-status" /><code>msg.payload <b>on</b></code><Check size={16} /></div></div></section></div>

        <section id="experience" className="story-track section-shell"><div className="story-intro reveal"><div className="eyebrow"><span className="eyebrow-dot" />{t.story.eyebrow}</div><h2>{t.story.title.split('\n').map((line) => <span key={line}>{line}<br /></span>)}</h2><p>{t.story.body}</p><div className="story-small"><FlowArrow size={18} />{t.story.small}</div><div className="tag-row">{t.story.tags.map((tag) => <span key={tag}>{tag}</span>)}</div></div><div className="story-stage"><div className="story-line" aria-hidden="true"><span className="story-line-progress" /></div><div className="story-image reveal"><img src="/assets/rivlen-iphone-mockup.png" width="851" height="1849" alt="Rivlen running inside an iPhone simulator mockup" /><div className="image-label"><span>02</span><span>{language === 'zh' ? '连接你的实例' : 'Connect your instance'}</span></div></div></div></section>

        <div className="scroll-chapter ha-chapter" id="features"><section className="ha-section section-shell"><div className="ha-copy reveal"><div className="eyebrow"><span className="eyebrow-dot" />{t.ha.eyebrow}</div><h2>{t.ha.title}</h2><p>{t.ha.body}</p><RoomResponse language={language} /></div><div className="form-stage"><div className="form-window-top"><span>Home Assistant</span><span className="window-dots"><i /><i /><i /></span></div><div className="form-heading"><span>{language === 'zh' ? '编辑节点' : 'Edit node'}</span><SlidersHorizontal size={18} /></div><div className="form-list">{t.ha.labels.map((label, index) => <label key={label}><span>{label}</span><div className="select-field"><span>{t.ha.values[index]}</span><CaretDown size={15} /></div></label>)}</div><div className="form-foot"><span className="form-status" />{language === 'zh' ? '从实例加载' : 'Loaded from instance'}<ArrowUpRight size={15} /></div></div></section></div>

        <div className="scroll-chapter debug-chapter"><section className="debug-section"><img className="debug-atmosphere" src="/assets/debug-atmosphere.png" alt="" aria-hidden="true" /><div className="debug-inner section-shell"><div className="debug-copy reveal"><div className="eyebrow eyebrow-light"><span className="eyebrow-dot" />{t.debug.eyebrow}</div><h2>{t.debug.title.split('\n').map((line) => <span key={line}>{line}<br /></span>)}</h2><p>{t.debug.body}</p><div className="debug-message"><span className="debug-pulse" /><span>{t.debug.pulse}</span><ArrowUpRight size={16} /></div></div><div className="debug-console"><div className="console-header"><span><Bug size={18} weight="fill" />Debug</span><span className="console-live"><i />LIVE</span></div><div className="console-lines">{t.debug.log.map((line) => <code key={line}>{line}</code>)}</div><div className="console-foot"><Broadcast size={16} />{t.debug.note}</div></div></div></section></div>

        <section className="gateway-section section-shell"><div className="gateway-art reveal"><div className="gateway-ring ring-one" /><div className="gateway-ring ring-two" /><div className="gateway-core"><QrCode size={54} weight="thin" /><span>Rivlen Gateway</span></div><div className="gateway-node node-a"><span />Node-RED</div><div className="gateway-node node-b"><LockKey size={15} />Private</div><div className="gateway-node node-c"><span />Phone</div></div><div className="gateway-copy reveal"><div className="eyebrow"><span className="eyebrow-dot" />{t.gateway.eyebrow}</div><h2>{t.gateway.title.split('\n').map((line) => <span key={line}>{line}<br /></span>)}</h2><p>{t.gateway.body}</p><ul>{t.gateway.points.map((point) => <li key={point}><Check size={16} weight="bold" />{point}</li>)}</ul><button className="text-link" type="button" onClick={() => scrollTo('download')}>{t.gateway.cta}<ArrowRight size={17} /></button></div></section>

        <section id="download" className="download-section section-shell"><div className="download-copy reveal"><div className="eyebrow"><span className="eyebrow-dot" />{t.download.eyebrow}</div><h2>{t.download.title.split('\n').map((line) => <span key={line}>{line}<br /></span>)}</h2><p>{t.download.body}</p></div><div className="download-panel reveal"><DownloadButton icon={<GooglePlayLogo size={23} weight="fill" />} label={t.download.play} href={downloadLinks.play} unavailable={t.download.unavailable} /><DownloadButton icon={<AndroidLogo size={23} weight="fill" />} label={t.download.pgyer} href={downloadLinks.pgyer} unavailable={t.download.unavailable} /><DownloadButton icon={<AppleLogo size={23} weight="fill" />} label={t.download.ios} href={downloadLinks.ios} unavailable={t.download.unavailable} /></div><div className="download-foot"><span>{t.download.foot}</span><img className="footer-mark" src="/assets/rivlen-mark.svg" alt="" /></div></section>
      </main>
    </div>
  );
}

function RoomResponse({ language }) {
  return <div className="room-response" aria-label={language === 'zh' ? '灯光、风扇和温度随动作响应' : 'Light, fan, and temperature respond to the action'}>
    <div className="room-light"><span className="room-light-glow" /><Lightbulb className="room-bulb" size={44} weight="fill" /><span>{language === 'zh' ? '客厅' : 'Living room'}</span></div>
    <div className="room-controls"><div className="room-dimmer"><Sun size={15} /><i><span /></i></div><div className="room-climate"><span className="room-fan"><Fan size={25} /></span><span><Thermometer size={18} /><b className="room-temperature-value">22</b>°</span></div></div>
  </div>;
}

function DownloadButton({ icon, label, href, unavailable }) {
  if (!href) return <button className="download-button is-disabled" type="button" title={unavailable}><span className="download-icon">{icon}</span><span className="download-label"><strong>{label}</strong><small>{unavailable}</small></span><WarningCircle size={18} /></button>;
  return <a className="download-button" href={href} target="_blank" rel="noreferrer"><span className="download-icon">{icon}</span><span className="download-label"><strong>{label}</strong><small>Download</small></span><ArrowUpRight size={18} /></a>;
}

export default App;
