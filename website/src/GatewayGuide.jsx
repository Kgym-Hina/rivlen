import { useEffect, useState } from 'react';
import { ArrowLeft, ArrowRight, Check, Copy, GlobeHemisphereWest, Moon, Sun, TerminalWindow, Sparkle, QrCode, ShieldCheck } from '@phosphor-icons/react';
import './gateway-guide.css';

const repository = 'https://github.com/Kgym-Hina/rivlen';
const addRepositoryURL = `https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=${encodeURIComponent(repository)}`;
const sourceCommand = `git clone ${repository}.git\ncd rivlen/gateway`;
const copy = {
  zh: {
    home: '返回 Rivlen', title: '让手机，连上你的 Flow。', intro: '安装网关，连接 Node-RED，再与 Rivlen 配对。',
    ai: '让 AI 帮你部署', aiBody: '复制提示词，粘贴给你的 AI Agent。它会先确认环境，再安装和配置。', prompt: '复制部署提示词', show: '查看提示词',
    copied: '已复制', copy: '复制', failed: '复制未成功，请选中文本手动复制。',
    manual: '自己动手', manualBody: '选择安装方式、访问方式和认证，下面的步骤会同步切换。替换示例地址并设置自己的密码。',
    method: '安装方式', network: '访问方式', auth: 'Node-RED 认证', docker: 'Docker Compose', native: '原生 Go', ha: 'Home Assistant App', lan: '仅局域网', https: '域名 + HTTPS',
    noAuth: '无需认证', admin: 'Node-RED 账号', basic: 'HA 用户名 + 密码', token: 'Node-RED Token',
    steps: ['准备环境', '获取网关', '写入配置', '启动并检查', '连接网络', '配对手机'],
    ready: '先准备好这些', readyBody: '选择一台能访问 Node-RED 的常开电脑或服务器。手机需要能访问这台电脑的网关地址。',
    requirements: ['已有可正常打开的 Node-RED 实例，记录完整地址和端口。', '在部署机器上准备 Git。Docker 方式需要 Docker Engine / Desktop 和 Compose；原生方式需要 Go 1.23 或更新版本。', '终端示例使用 macOS、Linux 或 Windows WSL 的 shell。安装位置可自行选择；需要外置硬盘时先进入对应目录。'],
    haGuide: {
      readyBody: '需要运行 Home Assistant OS 或带 Supervisor 的 Home Assistant，并已有可访问的 Node-RED 实例。',
      requirements: ['Home Assistant 设置中能看到 Apps；仅安装 Home Assistant Container 的环境没有 Supervisor，不能安装 Apps。', '准备 Node-RED 的直连地址和认证方式。默认建议先试 http://homeassistant:1880；Ingress 链接不能用于网关连接。', '手机需要能访问 Home Assistant 主机上的网关端口 8787。'],
      getBody: '通过 Home Assistant Apps 商店添加 Rivlen 仓库，然后从商店安装 Rivlen Gateway。',
      addButton: '在 Home Assistant 中添加仓库',
      addSteps: ['打开后确认添加 Rivlen Apps 仓库。', '回到 Apps 商店，找到 Rivlen Gateway 并选择安装。'],
      configBody: '安装完成后先打开 Rivlen Gateway 的“配置”页，填写下面这些选项，再启动 App。',
      fields: [['Node-RED 地址', '填写网关容器可直接访问的 Node-RED 地址和端口。默认 http://homeassistant:1880；不要使用 Ingress 地址。若该地址不可达，尝试 HA App 的内部主机名或本机映射端口。'], ['认证方式与凭据', '按顶部选择的认证方式填写：无认证、Node-RED Admin 账号、HA 账号密码，或 Node-RED Admin Token。只填写所需凭据。'], ['配对密码', '设置至少 12 个字符的独立密码。'], ['网关固定访问地址', '局域网使用时留空，二维码将使用你打开网关页的地址；反向代理时填最终 HTTPS 地址。']],
      startBody: '保存配置并启动 Rivlen Gateway。首次安装会从 GHCR 下载对应 HA 架构的镜像。',
      health: 'App 页的运行状态和 Watchdog 会检查网关进程。启动后选择“打开 Web UI”，再验证配对和 Node-RED 连接。',
      lanBody: '手机与 Home Assistant 在同一局域网时，浏览器打开 http://<HA 主机地址>:8787。若此端口被占用，可在 Rivlen Gateway 的“网络”页修改映射端口。',
      httpsBody: '将 HTTPS 反向代理转发到 Home Assistant 主机的 8787 端口，并启用 WebSocket。然后在“配置”页填写最终 HTTPS 地址。',
      browserURL: '网关页面地址', browserAddress: 'http://<HA 主机地址>:8787',
      issues: [['HA 里找不到仓库', '确认仓库地址为 https://github.com/Kgym-Hina/rivlen，并在 Apps 商店菜单的 Repositories 中刷新。只支持带 Supervisor 的安装。'], ['网关 App 无法启动', '检查配置页中的配对密码是否至少 12 位、Node-RED URL 是否为有效直连地址；打开 App 日志查看具体错误。'], ['Node-RED 返回 401', '选择与 Node-RED 直连端口一致的认证模式。HA Node-RED App 常用 HA 用户名和密码的 basic 模式；HA 长期令牌不能替代。'], ['二维码地址不对', '局域网场景清空“网关固定访问地址”并通过正确的 HA 主机地址打开 Web UI；公网反代场景填写完整 HTTPS URL。'], ['二维码过期或已使用', '回到网关网页重新生成二维码。'], ['Flow 可读，Debug 没消息', '确认 Node-RED Debug 节点已启用并收到消息，同时检查 HA 反向代理是否支持 WebSocket。']],
    },
    getBody: '在你选定的安装目录打开终端，获取源码。已下载源码时，直接进入其中的 gateway 文件夹。', source: '查看网关源码',
    configBody: '在 gateway 目录中创建 .env，写入下面的内容并替换占位符。不要把密码写进 Node-RED URL。',
    lanConfig: '将 192.168.1.10 换成网关电脑的局域网 IP。手机使用这个地址连接；0.0.0.0 只用于监听，不能作为配对地址。',
    httpsConfig: '将 flows.example.com 换成你的域名。此示例由同一台主机上的反向代理提供 HTTPS，网关端口只绑定本机。',
    urlHelp: 'RIVLEN_NODE_RED_URL 是网关访问 Node-RED 的地址。Docker 访问宿主机用 host.docker.internal；访问同一 Docker 网络里的 Node-RED 可用服务名；访问另一台电脑用它的局域网 IP。保留真实的端口和反向代理路径。',
    passwordHelp: '配对密码至少 12 个字符。这是你自己设置的网关密码，与 Node-RED / Home Assistant 的登录密码分别配置。',
    basicHelp: 'Home Assistant App 使用 basic 模式，填写能登录 HA 的专用账号和密码。Node-RED URL 要使用 App 的直连地址和已配置的端口，不要填 HA 首页或 Ingress 链接。这里不是 HA 长期访问令牌，也不是 Node-RED 的 Admin Token。启用“仅本地访问”的账号时，网关也必须从其允许的本地网络访问 HA。',
    adminHelp: '填写 Node-RED Admin API 账号和密码，账号需能读写 Flow。网关会获取并刷新 Admin Token。',
    tokenHelp: '填写 Node-RED Admin API 的 Bearer Token。不要同时配置用户名和密码。',
    override: '使用 Home Assistant App 时，再在 gateway 目录创建 compose.override.yaml。它也兼容尚未传递认证模式的旧版 Compose 配置。',
    startBody: '在 gateway 目录运行。Docker 会后台启动，并在 Docker 服务重启后自动恢复。',
    nativeStart: '在同一个终端加载 .env，构建并启动。进程在前台运行，关闭终端会停止；长期使用时可交给 systemd、launchd 或你的进程管理器。',
    health: '另开终端检查。HTTP 204 表示网关进程可访问；Node-RED 的连接和权限还需要在最后一步配对后确认。',
    lanBody: '电脑与手机连接同一局域网。允许防火墙从本地网络访问 TCP 8787，然后在手机浏览器打开网关地址。无需转发 Node-RED 端口。',
    httpsBody: '让域名指向你的反向代理，准备有效的 HTTPS 证书。以下 Caddy 配置适用于 Caddy 与网关运行在同一台主机上。已有代理时，按同样的目标配置即可。',
    proxyHelp: '代理必须转发 WebSocket，并保留 Host 和 X-Forwarded-Proto。若代理在容器内或另一台机器上，127.0.0.1 不会指向网关，需要改为双方可达的地址和绑定方式。',
    publicHelp: '公网访问使用 HTTPS。只公开网关入口，Node-RED 保持私有。此 Compose 示例显式设置 RIVLEN_PUBLIC_URL，二维码将使用该地址；修改地址后要重新生成二维码。',
    browserURL: '在电脑或手机浏览器打开', pairIntro: '网关地址能打开后，开始配对。',
    pairing: ['在网关网页输入你设置的配对密码，点击“生成配对二维码”。', '打开 Rivlen → 连接新实例 → 通过网关配对，扫描二维码。', '输入同一个网关配对密码，给设备命名并完成配对。', '打开一个 Flow，检查节点和 Home Assistant 实体；触发 Inject，再到 Debug 查看消息。'],
    invitation: '二维码 / 配对文件只能使用一次，10 分钟后过期。无法扫码时，可从网关网页下载配对文件，再在 Rivlen 中选择“导入配对文件”。',
    owner: '第一个完成配对的设备成为所有者，可在连接菜单中查看和撤销其他设备授权。配对文件不包含密码或设备 Token。',
    troubleshoot: '遇到问题', issues: [
      ['网页打不开', '确认网关正在运行、端口绑定正确、防火墙允许访问。手机不能使用 localhost 或 127.0.0.1 连接另一台电脑。'],
      ['配对密码错误', '网页和 App 都要使用 RIVLEN_PAIRING_PASSWORD。修改 .env 后，Docker 运行 docker compose up -d 重新创建容器；原生进程需重新加载环境并启动。'],
      ['Node-RED 返回 401', '检查认证方式：普通 Node-RED 使用 admin / Admin Token；Home Assistant App 直连端口使用 basic + HA 账号密码，并确认 compose.override.yaml 已生效。'],
      ['二维码中的地址不对', '检查 RIVLEN_PUBLIC_URL，它会覆盖浏览器地址。直接运行的网关可留空并从请求读取地址；当前 Compose 模板要求显式填写。'],
      ['二维码过期或已使用', '回到网关网页生成新的二维码，再扫描一次。'],
      ['Flow 可读，Debug 没消息', '检查代理的 WebSocket 支持，以及网关到 Node-RED 的 /comms 连通性；确保 Debug 节点启用并收到消息。'],
    ],
    maintain: '保留配对关系', maintainBody: 'Docker 的 gateway-data 卷、原生部署的 data/gateway.json，以及 HA App 的应用数据都保存网关身份和设备授权。迁移或更新时保留数据；HA App 数据会进入 Home Assistant 备份。更换配对密码不会撤销已有设备，请在 App 中撤销对应授权。',
    end: '网关已就绪，回到 Rivlen。', endLink: '获取 Rivlen', onThisPage: '本页步骤',
  },
  en: {
    home: 'Back to Rivlen', title: 'Connect your phone to your Flow.', intro: 'Install the gateway, connect Node-RED, then pair Rivlen.',
    ai: 'Let your AI deploy it', aiBody: 'Copy the prompt into your AI Agent. It will check your environment before installing and configuring the gateway.', prompt: 'Copy deployment prompt', show: 'View prompt',
    copied: 'Copied', copy: 'Copy', failed: 'Copy failed. Select the text and copy it manually.',
    manual: 'Install it yourself', manualBody: 'Choose an installation method, access type, and authentication. The steps below will adapt.',
    method: 'Installation', network: 'Access', auth: 'Node-RED authentication', docker: 'Docker Compose', native: 'Native Go', ha: 'Home Assistant App', lan: 'Local network', https: 'Domain + HTTPS',
    noAuth: 'No authentication', admin: 'Node-RED account', basic: 'HA username + password', token: 'Node-RED Token',
    steps: ['Prepare', 'Get the gateway', 'Configure', 'Start and check', 'Network access', 'Pair your phone'],
    ready: 'What you need', readyBody: 'Use an always-on computer or server that can reach Node-RED. Your phone must be able to reach the gateway on that computer.',
    requirements: ['A working Node-RED instance, including its full address and port.', 'Git on the deployment machine. Docker installs require Docker Engine / Desktop with Compose; native installs require Go 1.23 or newer.', 'Commands use a macOS, Linux, or Windows WSL shell. Choose an installation directory first, including an external drive when desired.'],
    haGuide: {
      readyBody: 'You need Home Assistant OS or a Home Assistant installation with Supervisor, plus a reachable Node-RED instance.',
      requirements: ['Home Assistant Settings must include Apps. Home Assistant Container without Supervisor cannot install Apps.', 'Have the direct Node-RED URL and its authentication method ready. Try http://homeassistant:1880 first; an Ingress URL cannot be used by the gateway.', 'Your phone must be able to reach port 8787 on the Home Assistant host.'],
      getBody: 'Add the Rivlen repository through the Home Assistant Apps store, then install Rivlen Gateway from the store.',
      addButton: 'Add repository in Home Assistant',
      addSteps: ['Confirm adding the Rivlen Apps repository when Home Assistant opens.', 'Return to the Apps store, find Rivlen Gateway, and select Install.'],
      configBody: 'After installation, open the Rivlen Gateway Configuration tab, fill in these options, and then start the App.',
      fields: [['Node-RED URL', 'Enter the direct address and port reachable from the gateway container. The default is http://homeassistant:1880; do not use an Ingress URL. If unreachable, try the Node-RED App host name or its mapped local port.'], ['Authentication and credentials', 'Choose the method selected above: none, Node-RED Admin account, HA username and password, or Node-RED Admin token. Fill only the needed credentials.'], ['Pairing password', 'Set a separate password with at least 12 characters.'], ['Fixed gateway URL', 'Leave empty on a LAN so the pairing QR uses the address of the page you opened. For a reverse proxy, enter its final HTTPS URL.']],
      startBody: 'Save the configuration and start Rivlen Gateway. On first install, Home Assistant downloads the image for its architecture from GHCR.',
      health: 'The App status and Watchdog check that the gateway process responds. After it starts, select Open Web UI, then verify pairing and Node-RED access.',
      lanBody: 'When your phone and Home Assistant share a LAN, open http://<HA host address>:8787. If that port is in use, change its mapping in the Rivlen Gateway Network tab.',
      httpsBody: 'Forward your HTTPS reverse proxy to port 8787 on the Home Assistant host and enable WebSocket. Then enter the final HTTPS URL in the App Configuration tab.',
      browserURL: 'Gateway page address', browserAddress: 'http://<HA host address>:8787',
      issues: [['Repository is missing in Home Assistant', 'Check that the repository URL is https://github.com/Kgym-Hina/rivlen, then refresh Repositories in the Apps store menu. Supervisor is required.'], ['Gateway App will not start', 'Check that the pairing password has at least 12 characters and the Node-RED URL is a valid direct URL. Open the App logs for the specific error.'], ['Node-RED returns 401', 'Choose the authentication method used by the direct Node-RED port. The HA Node-RED App commonly uses basic with an HA username and password; an HA long-lived token is not a substitute.'], ['Wrong address in the QR code', 'For LAN access, clear Fixed gateway URL and open Web UI through the correct HA host address. For a public reverse proxy, enter the full HTTPS URL.'], ['Expired or used QR code', 'Generate a new QR code on the gateway page.'], ['Flows load but Debug is empty', 'Confirm the Node-RED Debug node is enabled and receives messages. Check that the HA reverse proxy supports WebSocket.']],
    },
    getBody: 'Open a terminal in your chosen installation directory and get the source. If you already have it, enter its gateway folder.', source: 'View gateway source',
    configBody: 'Create .env in the gateway folder, paste the configuration below, and replace the placeholders. Keep credentials out of the Node-RED URL.',
    lanConfig: 'Replace 192.168.1.10 with the gateway computer’s LAN IP. Your phone connects to this address; 0.0.0.0 is a bind address, not a pairing URL.',
    httpsConfig: 'Replace flows.example.com with your domain. This example uses a TLS reverse proxy on the same host, with the gateway port bound to loopback.',
    urlHelp: 'RIVLEN_NODE_RED_URL is the address the gateway uses to reach Node-RED. From Docker, use host.docker.internal for the host, a service name on a shared Docker network, or a LAN IP for another computer. Include the actual port and any reverse proxy path.',
    passwordHelp: 'Use at least 12 characters for the gateway pairing password. Configure it separately from your Node-RED / Home Assistant login password.',
    basicHelp: 'For a Home Assistant App, use basic mode and a dedicated HA username and password. Use the App’s direct address and configured port, not the HA home page or an Ingress URL. An HA long-lived token or Node-RED Admin Token does not replace these credentials. Local-only HA accounts require the gateway to connect from an allowed local network.',
    adminHelp: 'Use a Node-RED Admin API account that can read and write flows. The gateway obtains and refreshes its Admin Token.',
    tokenHelp: 'Use a Node-RED Admin API Bearer Token. Do not also configure a username and password.',
    override: 'For the Home Assistant App, also create compose.override.yaml in the gateway folder. This works with older Compose files that do not pass the authentication mode.',
    startBody: 'Run in the gateway folder. Docker starts the gateway in the background and restarts it when the Docker service resumes.',
    nativeStart: 'Load .env, build, and start in the same terminal. The process runs in the foreground and stops when you close it. For persistent use, configure systemd, launchd, or your process manager.',
    health: 'Check from a second terminal. HTTP 204 confirms the gateway is reachable; verify upstream Node-RED access and permissions after pairing.',
    lanBody: 'Connect the phone and computer to the same LAN. Allow local network access to TCP port 8787 in the firewall, then open the gateway URL on your phone. Node-RED needs no port forwarding.',
    httpsBody: 'Point your domain to the reverse proxy and prepare valid HTTPS certificates. The Caddy example below assumes Caddy and the gateway run on the same host. With an existing proxy, configure the same upstream target.',
    proxyHelp: 'Forward WebSocket traffic and preserve Host and X-Forwarded-Proto. A proxy in a container or on another machine cannot reach the gateway via its own 127.0.0.1; adapt the bind address and upstream to a reachable private address.',
    publicHelp: 'Use HTTPS for internet access. Expose the gateway while keeping Node-RED private. This Compose example sets RIVLEN_PUBLIC_URL explicitly, so pairing uses that address. Generate a new QR code after changing it.',
    browserURL: 'Open in a browser', pairIntro: 'Once the gateway page opens, pair your phone.',
    pairing: ['Enter your pairing password on the gateway page and select “生成配对二维码” (Generate pairing QR).', 'Open Rivlen → Connect new instance → Pair through gateway, then scan the QR code.', 'Enter the same gateway pairing password, name the device, and complete pairing.', 'Open a Flow and check nodes and Home Assistant entities. Trigger Inject, then check Debug for messages.'],
    invitation: 'Each QR code / pairing file is single-use and expires after 10 minutes. Alternatively, download the pairing file from the gateway page and import it in Rivlen.',
    owner: 'The first paired device becomes the owner and can review or revoke other devices from the connection menu. Pairing files contain neither the password nor a device token.',
    troubleshoot: 'Troubleshooting', issues: [
      ['Gateway page does not open', 'Check the running process, port binding, and firewall. A phone cannot use localhost or 127.0.0.1 to reach another computer.'],
      ['Incorrect pairing password', 'Use RIVLEN_PAIRING_PASSWORD on both the gateway page and in the app. After editing .env, run docker compose up -d to recreate the container, or reload the environment and restart the native process.'],
      ['Node-RED returns 401', 'Use admin / an Admin Token for standard Node-RED, or basic with HA credentials for a Home Assistant App direct port. Check that compose.override.yaml is applied.'],
      ['Wrong address in the QR code', 'RIVLEN_PUBLIC_URL overrides the browser address. A directly run binary can leave it empty to read the request URL; the current Compose template requires an explicit value.'],
      ['Expired or used QR code', 'Generate a new QR code on the gateway page and scan again.'],
      ['Flows load but Debug is empty', 'Check WebSocket forwarding and /comms connectivity between the gateway and Node-RED. Enable the Debug node and make sure it receives messages.'],
    ],
    maintain: 'Keep your pairings', maintainBody: 'Docker stores gateway identity and authorizations in the gateway-data volume; native installs use data/gateway.json; the HA App uses its persistent app data, included in Home Assistant backups. Preserve this data when moving or updating. Changing the pairing password does not revoke existing devices—revoke them in the app.',
    end: 'Your gateway is ready.', endLink: 'Get Rivlen', onThisPage: 'On this page',
  },
};

function CopyButton({ text, t, label, primary = false }) {
  const [state, setState] = useState('idle');
  const handleCopy = async () => {
    try { await navigator.clipboard.writeText(text); setState('copied'); }
    catch { setState('failed'); }
  };
  useEffect(() => { if (state === 'idle') return; const timer = setTimeout(() => setState('idle'), 4000); return () => clearTimeout(timer); }, [state]);
  return <><button type="button" className={primary ? 'button button-primary' : 'guide-copy'} onClick={handleCopy}>{state === 'copied' ? <Check size={16} /> : <Copy size={16} />}{state === 'copied' ? t.copied : label || t.copy}</button><span className="guide-copy-status" role="status">{state === 'failed' ? t.failed : ''}</span></>;
}

function CodeBlock({ text, t, label }) {
  return <div className="guide-code"><div className="guide-code-bar"><span>{label}</span><CopyButton text={text} t={t} /></div><pre tabIndex={0}><code>{text}</code></pre></div>;
}

function Step({ number, title, children }) {
  return <section id={`step-${number}`} className="guide-step"><div className="guide-step-heading"><span>{String(number).padStart(2, '0')}</span><h2>{title}</h2></div>{children}</section>;
}

export default function GatewayGuide() {
  const [language, setLanguage] = useState(() => new URLSearchParams(window.location.search).get('lang') === 'en' ? 'en' : 'zh');
  const [dark, setDark] = useState(false);
  const [method, setMethod] = useState('docker');
  const [network, setNetwork] = useState('lan');
  const [auth, setAuth] = useState('none');
  const t = copy[language];
  const zh = language === 'zh';
  const chooseMethod = (nextMethod) => {
    setMethod(nextMethod);
    if (nextMethod === 'ha' && auth === 'none') setAuth('basic');
  };
  const publicURL = network === 'lan' ? 'http://192.168.1.10:8787' : 'https://flows.example.com';
  const nodeURL = method === 'docker' ? 'http://host.docker.internal:1880' : method === 'ha' ? 'http://homeassistant:1880' : 'http://127.0.0.1:1880';
  const env = [
    ...(method === 'docker' ? [`RIVLEN_BIND=${network === 'lan' ? '0.0.0.0' : '127.0.0.1'}`, 'RIVLEN_PORT=8787'] : [`RIVLEN_GATEWAY_LISTEN=${network === 'lan' ? '0.0.0.0' : '127.0.0.1'}:8787`, 'RIVLEN_DATA_FILE=./data/gateway.json']),
    `RIVLEN_NODE_RED_URL=${nodeURL}`, `RIVLEN_PUBLIC_URL=${publicURL}`, "RIVLEN_PAIRING_PASSWORD='REPLACE_WITH_YOUR_12_PLUS_CHARACTER_PASSWORD'",
    ...(auth === 'basic' ? ["RIVLEN_NODE_RED_AUTH_MODE=basic", "RIVLEN_NODE_RED_USERNAME='YOUR_HA_USERNAME'", "RIVLEN_NODE_RED_PASSWORD='YOUR_HA_PASSWORD'"] : []),
    ...(auth === 'admin' ? ['RIVLEN_NODE_RED_AUTH_MODE=admin', "RIVLEN_NODE_RED_USERNAME='YOUR_NODE_RED_USERNAME'", "RIVLEN_NODE_RED_PASSWORD='YOUR_NODE_RED_PASSWORD'"] : []),
    ...(auth === 'token' ? ['RIVLEN_NODE_RED_AUTH_MODE=admin', "RIVLEN_NODE_RED_TOKEN='YOUR_NODE_RED_ADMIN_TOKEN'"] : []),
  ].join('\n');
  const override = 'services:\n  rivlen-gateway:\n    environment:\n      RIVLEN_NODE_RED_AUTH_MODE: basic';
  const start = method === 'docker' ? 'docker compose up -d --build\ndocker compose ps\ndocker compose logs --tail=50 rivlen-gateway' : 'set -a\n. ./.env\nset +a\nmkdir -p data\ngo build -trimpath -o rivlen-gateway .\n./rivlen-gateway';
  const prompt = zh
    ? `请帮我安装并配置 Rivlen Gateway，让手机上的 Rivlen 连接现有 Node-RED。

源码：${repository}。先阅读 gateway/README.md、gateway/DOCS.md、gateway/config.yaml 和 gateway/main.go，以仓库当前版本为准。
方案：${t[method]}；网络：${t[network]}；Node-RED 认证：${t[auth === 'none' ? 'noAuth' : auth]}。

1. ${method === 'ha' ? '确认 Home Assistant 有 Supervisor（Settings 中可见 Apps）。通过 Apps 商店添加此仓库并安装 Rivlen Gateway；使用预构建 GHCR 多架构镜像。不要让用户 SSH 或手工安装 Docker。' : '检查部署主机、Node-RED 直连地址和认证方式、手机可访问的网关地址；公网方案还需域名与 HTTPS 代理信息。只询问缺失项。'}
2. ${method === 'ha' ? '在 Rivlen Gateway 的配置表单中填写 Node-RED URL、认证方式和对应凭据。HA Node-RED App 使用直连端口和 basic + HA 用户名密码；不要填 Ingress URL 或用 HA 长期令牌替代。' : '只部署 gateway/，保留 Node-RED、Flow 和已有网关数据。SSH 目标未经明确授权不要在服务器上构建；在本地或 CI 构建再上传。'}
3. ${method === 'ha' ? '设置至少 12 位的独立配对密码。局域网使用时固定网关 URL 留空；HTTPS 反代时填写最终 URL 并确认转发 WebSocket。保存并启动 App。' : '把凭据放入私有配置，不写进源码或日志。Docker / 原生 Go 按 gateway/README.md 操作；配对密码至少 12 位。'}
4. ${method === 'ha' ? '从 HA App 的 Open Web UI 按钮打开网关网页；默认局域网端口 8787。确保手机可访问 HA 主机该端口。' : '确保 Node-RED URL 从网关网络可达，二维码使用手机可访问的最终地址。仅公开网关，Node-RED 保持私有；公网必须使用 HTTPS。'}
5. 验证 /healthz 返回 204，再验证 Node-RED 认证、Flow 读取和 /comms。仅有健康检查成功不代表上游正常。
6. 指导我在网关网页输入配对密码并生成二维码，再在 Rivlen → 连接新实例 → 通过网关配对中扫描、输入同一密码并命名设备。邀请只能使用一次、10 分钟后过期；首个设备为所有者。不要在报告中回显密码。

最后给出真实访问地址、需要我亲自完成的步骤、配置与数据位置，以及未验证项。`
    : `Install and configure Rivlen Gateway so Rivlen on my phone can connect to my existing Node-RED.

Source: ${repository}. Read gateway/README.md, gateway/DOCS.md, gateway/config.yaml, and gateway/main.go first; follow the current repository version.
Setup: ${t[method]}; access: ${t[network]}; Node-RED authentication: ${t[auth === 'none' ? 'noAuth' : auth]}.

1. ${method === 'ha' ? 'Confirm Home Assistant has Supervisor (Apps is visible in Settings). Add this repository in the Apps store and install Rivlen Gateway from its prebuilt multi-architecture GHCR image. Do not ask the user to SSH or install Docker manually.' : 'Inspect the deployment host, direct Node-RED URL and authentication, and the gateway URL reachable by the phone. For internet access, confirm the domain and HTTPS proxy. Ask only for missing details.'}
2. ${method === 'ha' ? 'Fill in the Node-RED URL, authentication method, and matching credentials in the Rivlen Gateway configuration form. The HA Node-RED App uses its direct port and basic with an HA username and password; do not use an Ingress URL or substitute an HA long-lived token.' : 'Deploy gateway/ only. Preserve Node-RED, flows, and existing gateway data. Do not build on an SSH server without explicit authorization; build locally or in CI and upload.'}
3. ${method === 'ha' ? 'Set a separate pairing password of at least 12 characters. Leave the fixed gateway URL empty for LAN use; for an HTTPS proxy, enter the final URL and confirm WebSocket forwarding. Save and start the App.' : 'Keep credentials in private configuration, out of source and logs. Follow gateway/README.md for Docker or native Go. Use a separate pairing password of at least 12 characters.'}
4. ${method === 'ha' ? 'Open the gateway page with the HA App Open Web UI button. The default LAN port is 8787; ensure the phone can reach that port on the HA host.' : 'Make Node-RED reachable from the gateway and use the final phone-reachable URL in pairing. Expose only the gateway, keep Node-RED private, and require HTTPS for internet access.'}
5. Verify /healthz returns 204, then verify Node-RED authentication, flow reads, and /comms. A health check alone does not verify the upstream.
6. Guide me through entering the pairing password on the gateway page and generating a QR code, then scanning it in Rivlen → Connect new instance → Pair through gateway, entering the same password, and naming the device. Invitations are single-use and expire in 10 minutes; the first device becomes owner. Do not echo passwords in the report.

Return the real URL, any steps I must do myself, configuration and data locations, and anything left unverified.`;
  useEffect(() => { document.documentElement.lang = zh ? 'zh-CN' : 'en'; document.title = zh ? '网关安装与配对 · Rivlen' : 'Gateway setup & pairing · Rivlen'; }, [zh]);

  return <div className={`site gateway-guide ${dark ? 'is-dark' : ''}`}>
    <header className="nav-shell"><a className="brand" href="/"><img src="/assets/rivlen-mark.svg" alt="" /><span>Rivlen</span></a><a className="guide-home" href={`/?lang=${language}`}><ArrowLeft size={15} />{t.home}</a><div className="nav-tools"><button className="icon-button" onClick={() => setDark(!dark)} aria-label={zh ? '切换主题' : 'Toggle theme'}>{dark ? <Sun size={18} /> : <Moon size={18} />}</button><button className="language-toggle" onClick={() => setLanguage(zh ? 'en' : 'zh')} aria-label={zh ? 'English' : '中文'}><GlobeHemisphereWest size={17} /><span>{zh ? 'English' : '中文'}</span></button></div></header>
    <main className="guide-shell">
      <div className="guide-hero"><div className="eyebrow"><span className="eyebrow-dot" />Rivlen Gateway</div><h1>{t.title}</h1><p>{t.intro}</p></div>
      <section className="guide-ai"><div className="guide-ai-icon"><Sparkle size={27} /></div><div><h2>{t.ai}</h2><p>{t.aiBody}</p><div className="guide-ai-actions"><CopyButton text={prompt} t={t} label={t.prompt} primary /><a href="#manual">{t.manual}<ArrowRight size={16} /></a></div><details className="guide-prompt"><summary>{t.show}</summary><textarea readOnly value={prompt} aria-label={t.show} onFocus={(event) => event.target.select()} /></details></div></section>
      <section id="manual" className="guide-options"><div className="eyebrow"><TerminalWindow size={16} />{t.manual}</div><p>{t.manualBody}</p><div className="guide-option-grid">{[[t.method, method, chooseMethod, [['docker', t.docker], ['native', t.native], ['ha', t.ha]]], [t.network, network, setNetwork, [['lan', t.lan], ['https', t.https]]], [t.auth, auth, setAuth, [['none', t.noAuth], ['admin', t.admin], ['basic', t.basic], ['token', t.token]]]].map(([label, value, setter, options]) => <label key={label}><span>{label}</span><select value={value} onChange={(event) => setter(event.target.value)}>{options.map(([key, text]) => <option key={key} value={key}>{text}</option>)}</select></label>)}</div></section>
      <div className="guide-layout"><aside className="guide-toc"><span>{t.onThisPage}</span>{t.steps.map((step, index) => <a key={step} href={`#step-${index + 1}`}><small>{String(index + 1).padStart(2, '0')}</small>{step}</a>)}<a href="#troubleshooting">{t.troubleshoot}</a></aside><div className="guide-body">
        <Step number={1} title={t.steps[0]}><p>{method === 'ha' ? t.haGuide.readyBody : t.readyBody}</p><ul>{(method === 'ha' ? t.haGuide.requirements : t.requirements).map(item => <li key={item}>{item}</li>)}</ul>{method !== 'ha' && <div className="guide-tool-links"><a href="https://www.docker.com/get-started/" target="_blank" rel="noreferrer">Docker</a><a href="https://go.dev/dl/" target="_blank" rel="noreferrer">Go</a><a href="https://git-scm.com/downloads" target="_blank" rel="noreferrer">Git</a></div>}</Step>
        <Step number={2} title={t.steps[1]}><p>{method === 'ha' ? t.haGuide.getBody : t.getBody}</p>{method === 'ha' ? <><a className="button button-primary guide-ha-repo" href={addRepositoryURL} target="_blank" rel="noreferrer">{t.haGuide.addButton}<ArrowRight size={16} /></a><ol className="guide-pairing guide-ha-steps">{t.haGuide.addSteps.map(item => <li key={item}>{item}</li>)}</ol></> : <><CodeBlock text={sourceCommand} t={t} label="Terminal" /><a className="text-link" href={`${repository}/tree/main/gateway`} target="_blank" rel="noreferrer">{t.source}<ArrowRight size={15} /></a></>}</Step>
        <Step number={3} title={t.steps[2]}><p>{method === 'ha' ? t.haGuide.configBody : t.configBody}</p>{method === 'ha' ? <><ul className="guide-ha-fields">{t.haGuide.fields.map(([label, body]) => <li key={label}><strong>{label}</strong><span>{body}</span></li>)}</ul>{auth !== 'none' && <div className="guide-note"><ShieldCheck size={20} /><p>{t[`${auth}Help`]}</p></div>}</> : <><CodeBlock text={env} t={t} label=".env" /><CodeBlock text="chmod 600 .env" t={t} label="Terminal" /><p>{network === 'lan' ? t.lanConfig : t.httpsConfig}</p><p>{t.urlHelp}</p><p>{t.passwordHelp}</p>{auth !== 'none' && <div className="guide-note"><ShieldCheck size={20} /><p>{t[`${auth}Help`]}</p></div>}{method === 'docker' && auth === 'basic' && <><p>{t.override}</p><CodeBlock text={override} t={t} label="compose.override.yaml" /></>}</>}</Step>
        <Step number={4} title={t.steps[3]}><p>{method === 'ha' ? t.haGuide.startBody : method === 'docker' ? t.startBody : t.nativeStart}</p>{method !== 'ha' && <CodeBlock text={start} t={t} label="Terminal" />}<p>{method === 'ha' ? t.haGuide.health : t.health}</p>{method !== 'ha' && <CodeBlock text="curl -i http://127.0.0.1:8787/healthz" t={t} label="HTTP 204" />}</Step>
        <Step number={5} title={t.steps[4]}><p>{method === 'ha' ? (network === 'lan' ? t.haGuide.lanBody : t.haGuide.httpsBody) : (network === 'lan' ? t.lanBody : t.httpsBody)}</p>{method !== 'ha' && network === 'https' && <><CodeBlock text="flows.example.com {\n    reverse_proxy 127.0.0.1:8787\n}" t={t} label="Caddyfile" /><p>{t.proxyHelp}</p><p>{t.publicHelp}</p></>}<div className="guide-address"><span>{method === 'ha' ? t.haGuide.browserURL : t.browserURL}</span><code>{method === 'ha' ? (network === 'lan' ? t.haGuide.browserAddress : 'https://flows.example.com') : publicURL}</code></div></Step>
        <Step number={6} title={t.steps[5]}><div className="guide-pair-heading"><QrCode size={36} /><p>{t.pairIntro}</p></div><ol className="guide-pairing">{t.pairing.map(item => <li key={item}>{item}</li>)}</ol><p>{t.invitation}</p><p>{t.owner}</p></Step>
        <section id="troubleshooting" className="guide-step"><h2>{t.troubleshoot}</h2><div className="guide-faq">{(method === 'ha' ? t.haGuide.issues : t.issues).map(([title, body]) => <details key={title}><summary>{title}</summary><p>{body}</p></details>)}</div></section>
        <section className="guide-step guide-maintain"><ShieldCheck size={24} /><h2>{t.maintain}</h2><p>{t.maintainBody}</p></section>
      </div></div>
      <footer className="guide-footer"><span>{t.end}</span><a className="text-link" href="/#download">{t.endLink}<ArrowRight size={18} /></a></footer>
    </main>
  </div>;
}
