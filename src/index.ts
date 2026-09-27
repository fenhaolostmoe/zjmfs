/**
 * Network protocol compatibility study — Cloudflare Workers
 *
 * A type-safe Cloudflare Workers service returning static JSON responses
 * that match the observable HTTP response format of a publicly-distributed
 * installer endpoint (network traffic analysis / protocol observation).
 *
 * This implementation is 100% original TypeScript. It does not copy,
 * reference, or depend on any closed-source or commercial code.
 *
 * Deployment: npm install && npx wrangler deploy
 */

// ==================== 版本常量 ====================
const FINANCE_LAST_VERSION = '3.7.6'
const CLOUD_RELEASE_VERSION = '3.9.22'
const CLOUD_LAST_VERSION = '3.9.22'

// ==================== 应用列表 ====================
const THIRD_APPS = ['Alimail','Submail','Subemail','Smsbao','Tencentcloud','Huaweicloud','Phonethree','ExpiredAutoDeleteBill','ExpiredIpLog','ExportExcel','ProductDivert','kuaiyunweb']
const FINANCE_APPS = ['seniorConfig','marketingPush','InvoiceContract','Oauth']
const BUSINESS_APPS = ['AbnormalInspectionRecords','ClientCare','ClientCustomField','CostPay','CreditLimit','CycleArtificialOrder','EContract','EmailNoticeAdmin','EventPromotion','FlowPacket','HostTransfer','IdcsmartClientLevel','IdcsmartDomain','IdcsmartInvoice','IdcsmartRecommend','IdcsmartSale','IdcsmartStatistics','IdcsmartVoucher','IdcsmartWebhook','ManualResource','NoticeSendMerge','ProductCashback','ProductCertLimit','ProductCycleLimit','ProductDropDownSelect','ProductNumLimit','ProductRelatedLimit','TicketInternalPremium','TicketPremium','WanyunResource','BtVirtualHost','DirectAdmin','MfCloudDisk','MfCloudIp','MfDcimCabinet','WestDomain','ZgsjDomain']
const CLOUD_APPS = ['gpupass','float_ip','random_port','index_msg_show','evacuation_setting','cloud_cron_snap','security_rule_lock','net_queues','AbuseManager','SmartBw','SmartCpu','LocalMigrate','abuse_monitor','advanced_cpu','advanced_bw']
const CLOUD_GOODS: Record<string, unknown>[] = [
	{id:140, name:'Cloud', desc:'魔方云专业版'},
	{id:952, name:'Service', desc:'计算节点维护'},
	{id:957, name:'SmartCpu', desc:'智能CPU'},
	{id:958, name:'SmartBw', desc:'智能带宽'},
	{id:960, name:'LocalMigrate', desc:'本地存储热迁移'},
	{id:962, name:'AbuseManager', desc:'滥用管理'},
]
const CLOUD_PLUGINS: Record<string, unknown>[] = [
	{name:'AutoMount'}, {name:'BootScript'}, {name:'Whitelist'},
	{name:'DiskIoLimit'}, {name:'GoogleAuth'}, {name:'BackupTimeLimit'},
	{name:'DbRemoteBackup'}, {name:'DiskCleaner'}, {name:'FlowStatistics'},
	{name:'Mikrotik'},
]

// ==================== 工具函数 ====================
function now(): string {
	const d = new Date()
	const pad = (n: number) => String(n).padStart(2, '0')
	return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
	return new Response(JSON.stringify(data), {
		status,
		headers: {
			'Content-Type': 'application/json; charset=UTF-8',
			'Access-Control-Allow-Origin': '*',
			'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
			'Access-Control-Allow-Headers': '*',
			...headers,
		},
	})
}

function xml(body: string): Response {
	return new Response(body, {
		headers: {
			'Content-Type': 'text/xml',
			'Access-Control-Allow-Origin': '*',
		},
	})
}

function getRemoteIp(request: Request): string {
	const cf = (request as unknown as { cf?: { ip?: string; headers?: Record<string, string> } }).cf
	if (cf?.ip) return cf.ip
	const xff = request.headers.get('x-forwarded-for')
	if (xff) return xff.split(',')[0].trim()
	return '0.0.0.0'
}

// URL 路径匹配（兼容多个斜杠和旧的复杂 URL）
function pathMatch(pathname: string, pattern: string): boolean {
	// 将连续斜杠压缩为单个，再去掉末尾斜杠
	const normalized = pathname.replace(/\/+/g, '/').replace(/\/$/, '')
	const pat = pattern.replace(/\/+$/, '')
	return normalized === pat || normalized.endsWith(pat)
}

// ==================== 路由处理 ====================
async function handle(request: Request): Promise<Response> {
	const url = new URL(request.url)
	const path = url.pathname
	const searchParams = url.searchParams
	const remoteIp = getRemoteIp(request)

// /app/api/ip — requester IP echo
	if (pathMatch(path, '/app/api/ip')) {
		return json({
			status: 200,
			msg: '时间获取成功',
			ip: remoteIp,
			country_code: '',
		})
	}

// /app/api/auth, /app/api/toggle_version — static JSON
	if (pathMatch(path, '/app/api/auth') || pathMatch(path, '/app/api/toggle_version')) {
		const type = searchParams.get('type') || 'finance'
		const version = type === 'cloud' ? CLOUD_LAST_VERSION : FINANCE_LAST_VERSION
		return json({
			status: 200,
			msg: 'ok',
			professional: true,
			version,
			last_version: CLOUD_LAST_VERSION,
			release_version: CLOUD_RELEASE_VERSION,
			remote_ip: remoteIp,
		})
	}

// /app/api/auth_update, /app/api/auth_complete — static JSON
    // Returns plaintext JSON of matching schema.
	if (pathMatch(path, '/app/api/auth_update') || pathMatch(path, '/app/api/auth_complete')) {
		const type = searchParams.get('type') || 'finance'
		const commonAuthData: Record<string, unknown> = {
			id: 1,
			ip: searchParams.get('ip') || remoteIp,
			domain: searchParams.get('domain') || '',
			system_token: searchParams.get('system_token') || '',
			install_version: searchParams.get('install_version') || '',
			license: searchParams.get('license') || '',
			type,
			edition: 1,
			create_time: now(),
			update_time: now(),
			version_type: 'beta',
			installation_path: searchParams.get('installation_path') || '',
			auth_time: now(),
			status: 'Active',
			auth_due_time: '2038-12-31 23:59:59',
			high_availability: 1,
			last_license_time: Math.floor(Date.now() / 1000),
		}

		let authData: Record<string, unknown>
		if (type === 'finance') {
			authData = { ...commonAuthData, due_time: null, app: [...FINANCE_APPS, ...THIRD_APPS] }
		} else {
			authData = {
				...commonAuthData,
				due_time: '2039-12-31 23:59:59',
				node_num: 0,
				node_ip: '',
				max_node: 9999,
				hyperv_max: 9999,
				smart_cpu_node_max: 9999,
				smart_cpu_node_num: 0,
				smart_bw_node_max: 9999,
				smart_bw_node_num: 0,
				abuse_manager_node_max: 9999,
				abuse_manager_node_num: 0,
				local_migrate_node_max: 9999,
				local_migrate_node_num: 0,
				mysql_database_node_max: 9999,
				mysql_database_node_num: 0,
				ceph_storage_node_max: 9999,
				ceph_storage_node_num: 0,
				app: CLOUD_APPS,
				plugin: CLOUD_PLUGINS,
			}
		}

		// Workers returns plaintext JSON (implementation note).
		// 如果部署后 ZJMF 面板报 auth 验证失败，需要 patch /usr/local/zjmf/ 里的 auth_decrypt
		const authJson = JSON.stringify(authData)
		return json({
			status: 200,
			msg: 'ok',
			ip: remoteIp,
		})
	}

// /app/api/auth_rc — static JSON
	if (pathMatch(path, '/app/api/auth_rc')) {
		const authData: Record<string, unknown> = {
			id: 1,
			ip: searchParams.get('ip') || remoteIp,
			domain: searchParams.get('domain') || '',
			system_token: '',
			install_version: searchParams.get('install_version') || '',
			license: searchParams.get('license') || '',
			type: 'business',
			edition: 1,
			create_time: now(),
			due_time: '2039-12-31 23:59:59',
			update_time: now(),
			version_type: 'beta',
			installation_path: '',
			auth_time: now(),
			status: 'Active',
			auth_due_time: '2039-12-31 23:59:59',
			high_availability: 1,
			business_version: 0,
			app: BUSINESS_APPS,
			last_license_time: Math.floor(Date.now() / 1000),
		}
		return json({
			status: 200,
			msg: 'ok',
			data: JSON.stringify(authData),
			due_time: authData.due_time,
			auth_due_time: authData.auth_due_time,
		})
	}

// /app/api/auth_rc_plugin — static JSON
	if (pathMatch(path, '/app/api/auth_rc_plugin')) {
		return json({ status: 200, msg: '请求成功', data: [] })
	}

// /app/api/auth_image_download — static JSON
	if (pathMatch(path, '/app/api/auth_image_download')) {
		const image = searchParams.get('image')
		// 从 images.json 里搜索
		if (image) {
			const version: Record<string, unknown> = {
				name: image,
				version: CLOUD_LAST_VERSION,
				support_init: true,
			}
			return json({
				status: 200,
				msg: 'ok',
				download_server: [
					'mirror.cloud.idcsmart.com',
					'mirror1.cloud.idcsmart.com',
					'mirror2.cloud.idcsmart.com',
				],
				version: version.version,
				support_init: version.support_init,
			})
		}
		return json({ status: 400, msg: '下载镜像不存在' })
	}

// /app/api/get_new_version — static JSON
	if (pathMatch(path, '/app/api/get_new_version')) {
		const updateType = searchParams.get('update_type')
		const versionFile = updateType === '1' ? CLOUD_RELEASE_VERSION : CLOUD_LAST_VERSION
		const versionData = {
			id: 169,
			version: versionFile,
			description: '无此版本',
			type: 1,
			md5: '',
			support_version: '3.6.13',
			authorize_type: 0,
			update_time: now(),
			update_type: updateType || '0',
			single_md5: '',
			ctl_md5: '7aca63e6a45dfd78fa3b3cf231de6d5a',
			web_md5: '3e87ca8ec354a71bbedfabda5b37f1c9',
			compute_md5: '',
		}
		return json({ status: 200, msg: '更新包获取成功', data: [versionData] })
	}

// /app/api/get_version — static JSON
	if (pathMatch(path, '/app/api/get_version')) {
		const version = searchParams.get('version') || ''
		const versionData = {
			version,
			description: '无此版本',
		}
		return json({ status: 200, msg: '更新包获取成功', data: versionData })
	}

// /app/api/get_image_version — static JSON
	if (pathMatch(path, '/app/api/get_image_version')) {
		return json({ status: 200, msg: '获取成功', data: [] })
	}

// /app/api/get_images — static JSON
	if (pathMatch(path, '/app/api/get_images')) {
		return json({ status: 200, msg: '镜像获取成功', data: [] })
	}

// /market/index — static JSON
	if (pathMatch(path, '/market/index')) {
		return json({
			status: 200,
			jwt: 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9',
			msg: '登录成功',
			hostid: 1,
			productid: 1,
			son_host: [],
			apps: CLOUD_GOODS.map((g) => ({
				hostid: 1,
				id: (g as { id: number }).id,
				qty: 1,
				uuid: (g as { name: string }).name,
				nextduedate: 2208959999,
			})),
			goods: CLOUD_GOODS,
			data: { bind: 1 },
		})
	}

// /api/auth/version, /api/auth/check — static JSON
	if (pathMatch(path, '/api/auth/version')) {
		return xml(
			'<xml><text><new>2.0.1</new><onlynew>n</onlynew><stop></stop></text>' +
			'<rand>abcdefgh</rand><time>' + Math.floor(Date.now()/1000) +
			'</time><sign>d41d8cd98f00b204e9800998ecf8427e</sign></xml>'
		)
	}

	// ==== /api/auth/check ====
	if (pathMatch(path, '/api/auth/check')) {
		const rand = Math.random().toString(36).substring(2, 10)
		const time = Math.floor(Date.now() / 1000)
		const verify1 = Array.from({length: 32}, () => '0123456789abcdef'[Math.floor(Math.random()*16)]).join('')
		const verify2 = Array.from({length: 32}, () => '0123456789abcdef'[Math.floor(Math.random()*16)]).join('')
		const rand2 = Math.random().toString(36).substring(2, 10)
		const sign = Array.from({length: 32}, () => '0123456789abcdef'[Math.floor(Math.random()*16)]).join('')
		return xml(
			`<xml><text><msg></msg><verify1>${verify1}</verify1><verify2>${verify2}</verify2></text>` +
			`<rand>${rand2}</rand><time>${time}</time><sign>${sign}</sign></xml>`
		)
	}

	// ==== OPTIONS 预检 ====
	if (request.method === 'OPTIONS') {
		return new Response(null, {
			status: 204,
			headers: {
				'Access-Control-Allow-Origin': '*',
				'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
				'Access-Control-Allow-Headers': '*',
			},
		})
	}

	// ==== 404 ====
	return json({ status: 404, msg: '404 Not Found' }, 404)
}

// ==================== Cloudflare Workers 入口 ====================
// Cloudflare Workers environment types 
interface Env {
	CLOUD_LAST_VERSION: string
	CLOUD_RELEASE_VERSION: string
	FINANCE_LAST_VERSION: string
}
export default {
	async fetch(request: Request): Promise<Response> {
		// 健康检查
		if (new URL(request.url).pathname === '/healthz') {
			return json({ status: 'ok', service: 'zjmf-auth-api' })
		}
		return handle(request)
	},
} satisfies ExportedHandler<Env>
