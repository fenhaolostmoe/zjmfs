package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/cavaliergopher/grab/v3"
)

// 日志文件相关
var (
	LogFileName      string
	logger           *log.Logger
)

// 全局配置变量
var (
	// 环境检测状态
	EnvironmentStatus      int
	OSReleaseVersionNum    int
	OSReleaseVersionString string
	DefaultRepo            string
	OSReleaseVersionB      bool
	OSReleaseVersionL      bool
	OSReleaseVersionStatus bool
	CheckSElinuxStatus     bool
	LinuxKernelVersion     string
	LinuxKernelVersionStatus bool
	SkipKernelCheck        bool
	RootFreeSpaces         int64
	RootFreeSpacesStatus   bool
	HomeFreeSpaces         int64
	HomeFreeSpacesStatus   bool
	NetworkStatus          bool
	LightNetworkMode       bool

	// 网络配置
	ExternalIPaddress  string
	LocalIPaddress     string
	ChoosesInterface   string
	ChoosesInterfaceName string
	ChoosesInterfaceMac  string
	ChoosesInterfaceNum  int
	ChoosesTrunkMode     bool

	// 安装配置
	ZjmfInstallType   int
	ChooseInstallType int
	InstallArea       string
	InstallVersion    string
	SpecifiedVersion  string
	OnlyInstallController bool

	// 认证配置
	CtlAuthUsername string
	CtlAuthPassword string
	NodeAuthUsername string
	NodeAuthPassword string

	// 数据库配置
	MysqlRootPassword  string
	MysqlCloudPassword string

	// Docker 配置
	DockerWeb string
	DockerCtl string

	// ZJMF 配置
	InterfaceConfigPath string
	InterfaceRoutePath  string
	WebAdminPath        string
	WebAdminPassword    string
	ZjmfLicense         string
	LicenseRequest      interface{}

	// 时间相关
	StartTime time.Time
)

// init 在 line 560-680
func init() {
	makemap_states()
	// defaultLetters = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	defaultLetters = []byte("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
}

// states map 初始化
func makemap_states() {
	states = map[int]string{
		1:  "Running",
		2:  "Stopped",
		3:  "Pending",
		4:  "Success",
		5:  "Failed",
		6:  "Timeout",
		7:  "Canceled",
		8:  "Unknown",
		9:  "Created",
		10: "Waiting",
		11: "Ready",
	}
}

// defaultLetters 在 line 560
var defaultLetters []byte

// states map 在 line 561+
var states map[int]string

// license 变量
var license string


// ============ Logger 函数 (line 33-64) ============

func logger_Println(v ...interface{}) {
	if logger != nil {
		logger.Println(v...)
	} else {
		log.Println(v...)
	}
}

func logger_Printf(format string, v ...interface{}) {
	if logger != nil {
		logger.Printf(format, v...)
	} else {
		log.Printf(format, v...)
	}
}

func logger_Print(v ...interface{}) {
	if logger != nil {
		logger.Print(v...)
	} else {
		log.Print(v...)
	}
}

// ============ PathExists (line 99-107) ============

func PathExists(path string) bool {
	_, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return false
		}
		return false
	}
	return true
}

// ============ GetPathFreeSpaces (line 207-214) ============

func GetPathFreeSpaces(path string) (int64, error) {
	var stat syscall.Statfs_t
	err := syscall.Statfs(path, &stat)
	if err != nil {
		return 0, err
	}
	// free blocks * block size
	return int64(stat.Bavail) * int64(stat.Bsize), nil
}

// ============ RandomString (line 562-577) ============

func RandomString(length int) string {
	b := make([]byte, length)
	for i := range b {
		b[i] = defaultLetters[time.Now().UnixNano()%int64(len(defaultLetters))]
	}
	return string(b)
}

// ============ BashRunCommand (line 217-227) ============

func BashRunCommand(cmd string) {
	c := exec.Command("bash", "-c", cmd)
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	c.Run()
}

// ============ RunCommand (line 230-299) ============

func RunCommand(name string, args ...string) error {
	logger_Printf("[执行] %s %v", name, args)
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	err := cmd.Run()
	if err != nil {
		logger_Printf("[错误] %v", err)
	}
	return err
}

// ============ RunCommandOutput (line 230-239) ============

func RunCommandOutput(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	return buf.String(), err
}


// ============ RpmInstall (line 372-397) ============

func RpmInstall(rpmPath string) error {
	if strings.HasSuffix(rpmPath, ".rpm") {
		logger_Printf("[安装RPM] %s", rpmPath)
		return RunCommand("rpm", "-Uvh", rpmPath)
	}
	return nil
}

// ============ PipInstall (line 400-425) ============

func PipInstall(pythonVersion int, pkgPath string) error {
	pipCmd := fmt.Sprintf("pip%d", pythonVersion)
	logger_Printf("[安装PIP] %s %s", pipCmd, pkgPath)
	return RunCommand(pipCmd, "install", "--no-deps", pkgPath)
}


// ============ VersionOrdinal (line 428-454) ============

func VersionOrdinal(version string) int {
	parts := strings.Split(version, ".")
	if len(parts) == 0 {
		return 0
	}
	var result int
	for _, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil {
			continue
		}
		result = result*1000 + n
	}
	return result
}

// ============ ReadFileAll (line 457-462) ============

func ReadFileAll(filename string) (string, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

// ============ WriteCoverFile (line 465-471) ============

func WriteCoverFile(filename, content string) error {
	return os.WriteFile(filename, []byte(content), 0644)
}

// ============ WriteAppendFile (line 474-481) ============

func WriteAppendFile(filename, content string) error {
	f, err := os.OpenFile(filename, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.WriteString(content)
	return err
}

// ============ InitConfig (line 484-517) ============

func InitConfig(filename string) (map[string]string, error) {
	config := make(map[string]string)

	f, err := os.OpenFile(filename, os.O_RDONLY, 0644)
	if err != nil {
		return config, nil // 文件不存在返回空map
	}
	defer f.Close()

	reader := bufio.NewReader(f)
	for {
		line, _, readErr := reader.ReadLine()
		if readErr != nil {
			break
		}
		lineStr := strings.TrimSpace(string(line))
		if lineStr == "" || strings.HasPrefix(lineStr, "#") {
			continue
		}
		parts := strings.SplitN(lineStr, "=", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			value := strings.TrimSpace(parts[1])
			config[key] = value
		}
	}
	return config, nil
}

// ============ GetUrl (line 540-557) ============

func GetUrl(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

// ============ PostForm (line 520-537) ============

func PostForm(url string, data url.Values) (string, error) {
	resp, err := http.PostForm(url, data)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

// ============ CheckFileStatus (line 580-594) ============

func CheckFileStatus(filename string) bool {
	if PathExists(filename) {
		info, err := os.Stat(filename)
		if err != nil {
			return false
		}
		return info.Size() > 0
	}
	return false
}

// ============ DeCompression (line 597-623) ============

func DeCompression(tarFile, destPath string) error {
	logger_Printf("[解压] %s -> %s", tarFile, destPath)
	if strings.HasSuffix(tarFile, ".tar.gz") || strings.HasSuffix(tarFile, ".tgz") {
		return RunCommand("tar", "-zxvf", tarFile, "-C", destPath)
	} else if strings.HasSuffix(tarFile, ".tar") {
		return RunCommand("tar", "-xvf", tarFile, "-C", destPath)
	} else if strings.HasSuffix(tarFile, ".zip") {
		return RunCommand("unzip", "-o", tarFile, "-d", destPath)
	}
	return fmt.Errorf("unsupported archive format: %s", tarFile)
}

// ============ ListAllLocalIpAddress (line 626-652) ============

func ListAllLocalIpAddress() []string {
	var ips []string
	interfaces, err := net.Interfaces()
	if err != nil {
		return ips
	}
	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip != nil && ip.To4() != nil {
				ips = append(ips, ip.String())
			}
		}
	}
	return ips
}


// ============ DownloadFile (line 159-202) ============

func DownloadFile(url, destPath string) error {
	maxRetries := 3
	retryCount := 0

	for retryCount < maxRetries {
		retryCount++
		logger_Printf("[下载] %s", url)

		req, err := grab.NewRequest(destPath, url)
		if err != nil {
			logger_Printf("[错误] 创建下载请求失败: %v", err)
			time.Sleep(10 * time.Second)
			continue
		}

		client := grab.NewClient()
		resp := client.Do(req)

		if err := resp.Err(); err != nil {
			logger_Printf("[错误] 下载失败 (尝试 %d/%d): %v", retryCount, maxRetries, err)
			if PathExists(destPath) {
				os.Remove(destPath)
			}
			time.Sleep(10 * time.Second)
			continue
		}

		logger_Printf("[完成] 下载成功: %s -> %s (%.2f MB)",
			url, destPath, float64(resp.Size())/(1024*1024))
		return nil
	}

	return fmt.Errorf("下载失败，已重试 %d 次", maxRetries)
}

// ============ WriteConfig (line 847-885) ============

func WriteConfig(filename string, config map[string]string) error {
	var buf strings.Builder
	for k, v := range config {
		buf.WriteString(fmt.Sprintf("%s=%s\n", k, v))
	}
	return WriteCoverFile(filename, buf.String())
}

// ============ CheckSElinux (line 1012-1032) ============

func CheckSElinux() bool {
	output, err := RunCommandOutput("getenforce")
	if err != nil {
		logger_Printf("[检查SELinux] 无法获取状态，假定已禁用")
		CheckSElinuxStatus = true
		return true
	}

	output = strings.TrimSpace(strings.ToLower(output))
	if strings.Contains(output, "disabled") || strings.Contains(output, "permissive") {
		logger_Printf("[检查SELinux] %s (OK)", output)
		CheckSElinuxStatus = true
		return true
	}

	logger_Printf("[警告] SELinux 未禁用: %s，尝试禁用...", output)
	RunCommand("setenforce", "0")
	RunCommand("sed", "-i", "s/SELINUX=enforcing/SELINUX=disabled/g", "/etc/selinux/config")
	CheckSElinuxStatus = true
	return true
}

// ============ CheckSystemRelease (line 954-1010) ============

func CheckSystemRelease() {
	// 检查 /etc/os-release
	osReleaseConfig, _ := InitConfig("/etc/os-release")
	centosRelease, _ := ReadFileAll("/etc/centos-release")
	redhatRelease, _ := ReadFileAll("/etc/redhat-release")

	logger_Printf("[检查系统] os-release: %v", osReleaseConfig)

	if name, ok := osReleaseConfig["ID"]; ok {
		OSReleaseVersionString = name
		logger_Printf("[检查系统] ID=%s", name)
	}

	if versionId, ok := osReleaseConfig["VERSION_ID"]; ok {
		OSReleaseVersionB = strings.HasPrefix(versionId, "7")
		OSReleaseVersionL = strings.HasPrefix(versionId, "8")
		n, _ := strconv.Atoi(versionId)
		OSReleaseVersionNum = n
		logger_Printf("[检查系统] VERSION_ID=%s, CentOS7=%v, CentOS8=%v",
			versionId, OSReleaseVersionB, OSReleaseVersionL)
	}

	// 如果 os-release 找不到，尝试从 centos-release 提取
	if OSReleaseVersionNum == 0 {
		releaseStr := centosRelease + redhatRelease
		re := regexp.MustCompile(`(\d+)`)
		matches := re.FindAllString(releaseStr, -1)
		if len(matches) > 0 {
			n, _ := strconv.Atoi(matches[0])
			OSReleaseVersionNum = n
			OSReleaseVersionB = n == 7
			OSReleaseVersionL = n == 8
			logger_Printf("[检查系统] 从release文件解析版本: %d", n)
		}
	}

	if OSReleaseVersionNum == 7 {
		DefaultRepo = "http://mirror.cloud.idcsmart.com/cloud/packages/c7"
	} else if OSReleaseVersionNum == 8 {
		DefaultRepo = "http://mirror.cloud.idcsmart.com/cloud/packages/c8"
	}

	OSReleaseVersionStatus = OSReleaseVersionB || OSReleaseVersionL
	if !OSReleaseVersionStatus {
		logger_Printf("[错误] 不支持的系统版本: %d，仅支持 CentOS 7/8", OSReleaseVersionNum)
	} else {
		logger_Printf("[检查系统] CentOS %d - OK", OSReleaseVersionNum)
	}
}

// ============ CheckKernelVersion (line 1054-1095) ============

func CheckKernelVersion() {
	if SkipKernelCheck {
		logger_Printf("[跳过] 内核版本检查")
		LinuxKernelVersionStatus = true
		return
	}

	output, err := RunCommandOutput("uname", "-r")
	if err != nil {
		logger_Printf("[错误] 无法获取内核版本: %v", err)
		LinuxKernelVersionStatus = false
		return
	}

	LinuxKernelVersion = strings.TrimSpace(output)
	logger_Printf("[检查内核] 当前版本: %s", LinuxKernelVersion)

	// 检查是否为 5.4 LT 内核
	re := regexp.MustCompile(`^(\d+)\.(\d+)`)
	matches := re.FindStringSubmatch(LinuxKernelVersion)
	if len(matches) >= 3 {
		major, _ := strconv.Atoi(matches[1])
		minor, _ := strconv.Atoi(matches[2])
		if major >= 5 && minor >= 4 {
			LinuxKernelVersionStatus = true
			logger_Printf("[检查内核] 版本满足要求 (>= 5.4)")
		} else {
			logger_Printf("[警告] 当前内核版本过低，推荐使用 5.4.166 LT 内核")
			// 尝试安装推荐内核
			if OSReleaseVersionB {
				kernelRpm := fmt.Sprintf("%s/kernel/5.4.166/kernel-lt-5.4.166-1.el7.elrepo.x86_64.rpm", DefaultRepo)
				logger_Printf("[安装内核] %s", kernelRpm)
				BashRunCommand(fmt.Sprintf("yum -y install %s", kernelRpm))
				logger_Printf("[提示] 内核安装完成，请重启系统后重新运行安装程序")
			}
			LinuxKernelVersionStatus = true // 即使版本低也继续安装
		}
	}
}


// ============ CheckRootSpaces (line 1034-1042) ============

func CheckRootSpaces() {
	free, err := GetPathFreeSpaces("/")
	if err != nil {
		logger_Printf("[错误] 获取根分区空间失败: %v", err)
		RootFreeSpacesStatus = false
		return
	}
	RootFreeSpaces = free / (1024 * 1024) // MB
	logger_Printf("[检查磁盘] 根分区剩余: %d MB", RootFreeSpaces)
	if RootFreeSpaces >= 50000 { // 至少 50GB
		RootFreeSpacesStatus = true
		logger_Printf("[检查磁盘] 根分区空间充足")
	} else {
		RootFreeSpacesStatus = false
		logger_Printf("[错误] 根分区空间不足，需要至少 50GB 剩余空间")
	}
}

// ============ CheckHomeSpaces (line 1044-1052) ============

func CheckHomeSpaces() {
	free, err := GetPathFreeSpaces("/home")
	if err != nil {
		// /home 可能不存在，就用 / 的空间
		free, _ = GetPathFreeSpaces("/")
	}
	HomeFreeSpaces = free / (1024 * 1024)
	logger_Printf("[检查磁盘] /home 剩余: %d MB", HomeFreeSpaces)
	if HomeFreeSpaces >= 200000 { // 至少 200GB
		HomeFreeSpacesStatus = true
		logger_Printf("[检查磁盘] /home 空间充足")
	} else {
		HomeFreeSpacesStatus = false
		logger_Printf("[警告] /home 空间可能不足，推荐至少 200GB")
	}
}

// ============ CheckNetwork (line 1121-1142) ============

func CheckNetwork() {
	// 检查 DNS 配置
	if !PathExists("/etc/resolv.conf") {
		logger_Printf("[警告] /etc/resolv.conf 不存在")
		NetworkStatus = false
		return
	}

	// 尝试 ping 公共 DNS
	err := exec.Command("ping", "-c", "1", "-W", "3", "8.8.8.8").Run()
	if err != nil {
		logger_Printf("[警告] 无法访问外网 (8.8.8.8)")
		// 可能在国内，尝试 mirror 连通性
		err2 := exec.Command("curl", "-s", "--connect-timeout", "5", 
			"http://mirror.cloud.idcsmart.com").Run()
		if err2 != nil {
			logger_Printf("[错误] 网络不可用")
			NetworkStatus = false
			return
		}
	}

	NetworkStatus = true
	logger_Printf("[检查网络] 网络连接正常")
}

// ============ RequestLicense (line 1212-1230) ============

func RequestLicense() error {
	logger_Printf("[请求License] 正在从服务器获取授权...")

	// 获取机器码
	hostname, _ := os.Hostname()
	macAddr := ""
	ips := ListAllLocalIpAddress()
	if len(ips) > 0 {
		for _, iface := range networkInterfaces() {
			if iface.Flags&net.FlagUp != 0 {
				macAddr = iface.HardwareAddr.String()
				break
			}
		}
	}

	// 构造请求
	reqData := url.Values{}
	reqData.Set("hostname", hostname)
	reqData.Set("mac", macAddr)
	reqData.Set("ip", strings.Join(ips, ","))
	reqData.Set("version", "cloud_new")
	reqData.Set("license", ZjmfLicense)

	resp, err := PostForm("http://mirror.cloud.idcsmart.com/cloud/license/verify", reqData)
	if err != nil {
		logger_Printf("[警告] License 验证请求失败: %v", err)
		return err
	}

	logger_Printf("[License响应] %s", resp)
	return nil
}

// networkInterfaces 辅助函数
func networkInterfaces() []net.Interface {
	ifaces, _ := net.Interfaces()
	return ifaces
}

// ============ CheckLicense (line 1233-1276) ============

func CheckLicense() {
	logger_Printf("[检查License] %s", ZjmfLicense)

	// 本地验证 license 格式
	if ZjmfLicense == "" {
		logger_Printf("[提示] 未提供License，将使用默认评估模式")
		return
	}

	// 尝试远程验证
	err := RequestLicense()
	if err != nil {
		logger_Printf("[警告] License验证失败，但将继续安装")
	} else {
		logger_Printf("[检查License] 验证完成")
	}
}

// ============ ChooseComputeNetworkInterface (line 91-1200) ============

func ChooseComputeNetworkInterface() {
	logger_Printf("[网络配置] 检测可用网卡...")

	ifaces, err := net.Interfaces()
	if err != nil {
		logger_Printf("[错误] 获取网卡列表失败: %v", err)
		return
	}

	var validIfaces []net.Interface
	for _, iface := range ifaces {
		if iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		if iface.Flags&net.FlagUp == 0 {
			continue
		}
		if strings.HasPrefix(iface.Name, "virbr") ||
		   strings.HasPrefix(iface.Name, "docker") ||
		   strings.HasPrefix(iface.Name, "br-") {
			continue
		}
		validIfaces = append(validIfaces, iface)
	}

	logger_Printf("[网络配置] 发现 %d 个有效网卡", len(validIfaces))
	for i, iface := range validIfaces {
		addrs, _ := iface.Addrs()
		ipStr := ""
		for _, a := range addrs {
			if ipNet, ok := a.(*net.IPNet); ok && ipNet.IP.To4() != nil {
				ipStr = ipNet.IP.String()
				break
			}
		}
		logger_Printf("  [%d] %s (%s) MAC: %s IP: %s",
			i, iface.Name, iface.Flags, iface.HardwareAddr, ipStr)
	}

	if len(validIfaces) == 1 {
		ChoosesInterface = validIfaces[0].Name
		ChoosesInterfaceName = validIfaces[0].Name
		ChoosesInterfaceMac = validIfaces[0].HardwareAddr.String()
		ChoosesInterfaceNum = 0
		logger_Printf("[网络配置] 自动选择: %s", ChoosesInterface)
	}
}


// ============ SelectVersion (line 1282-1328) ============

func SelectVersion() {
	if OnlyInstallController {
		// 仅安装控制器模式
		logger_Printf("[版本选择] 仅控制器模式")
		InstallVersion = "latest"
		return
	}

	if SpecifiedVersion != "" {
		// 用户指定了版本
		InstallVersion = SpecifiedVersion
		logger_Printf("[版本选择] 使用指定版本: %s", InstallVersion)
		return
	}

	// 检查 License 是否包含版本信息
	if ZjmfLicense != "" {
		// 从 License 请求响应中获取版本
		// 这里简化处理
		InstallVersion = "latest"
	} else {
		InstallVersion = "latest"
	}

	logger_Printf("[版本选择] 安装版本: %s", InstallVersion)
}

// ============ SelectLicenseVersion (line 1352-1359) ============

func SelectLicenseVersion() {
	logger_Printf("[License版本] 使用 License 中的版本信息")
	if ZjmfLicense != "" {
		SelectVersion()
	}
}

// ============ CollectMasterInstallConfig (line 1330-1339) ============

func CollectMasterInstallConfig() {
	logger_Printf("[配置收集] Master 安装配置")
	// 收集 Master 节点的安装参数
}

// ============ CollectControllerInstallConfig (line 1341-1350) ============

func CollectControllerInstallConfig() {
	logger_Printf("[配置收集] Controller 安装配置")
	// 收集 Controller 节点的安装参数
}

// ============ CollectComputeInstallConfig (line 1361-1386) ============

func CollectComputeInstallConfig() {
	logger_Printf("[配置收集] Compute 安装配置")
	// 收集计算节点参数
}

// ============ CollectComputeNerworkModeConfig (line 1388-1405) ============

func CollectComputeNerworkModeConfig() {
	logger_Printf("[配置收集] Compute 网络模式配置")
	if LightNetworkMode {
		logger_Printf("[网络模式] 轻量模式 (不配置 OVS)")
	} else {
		logger_Printf("[网络模式] OVS 模式")
	}
}

// ============ DownloadAndInstallPublicPackages (line 1553-1632) ============

func DownloadAndInstallPublicPackages() {
	logger_Printf("[公共包] 开始下载并安装公共依赖包...")

	packages := []string{
		"jq",
		"aria2",
		"ca-certificates",
		"curl",
		"wget",
	}

	if OSReleaseVersionB {
		packages = append(packages, "http://mirror.cloud.idcsmart.com/cloud/packages/c7/rpms-nodes.tar.gz")
	} else if OSReleaseVersionL {
		packages = append(packages, "http://mirror.cloud.idcsmart.com/cloud/packages/c8/rpms-nodes.tar.gz")
	}

	// 下载 bin 工具
	binTar := fmt.Sprintf("%s/bin.tar.gz", DefaultRepo)
	logger_Printf("[下载] bin 工具包: %s", binTar)
	DownloadFile(binTar, "/home/zjmf/download/bin.tar.gz")
	DeCompression("/home/zjmf/download/bin.tar.gz", "/home/zjmf/bin")

	// 解压 jq
		// systemctl enable openvswitch
}

// ============ InstallPublicService (line 1634-1653) ============

func InstallPublicService() {
	logger_Printf("[服务安装] 安装公共服务...")

	// 启用和重启基础服务
	BashRunCommand("systemctl enable openvswitch")
	BashRunCommand("systemctl restart openvswitch")
}

// ============ InitializationPublicService (line 1655-1703) ============

func InitializationPublicService() {
	logger_Printf("[初始化] 公共服务初始化...")

	// 创建基础目录
	BashRunCommand("mkdir -p /home/zjmf/bin /home/zjmf/download /home/zjmf/share")
	BashRunCommand("mkdir -p /home/zjmf/dashboard /home/zjmf/controller")

	// 设置权限
	BashRunCommand("chmod +x /usr/local/bin/*")

	// 创建 zjmf 用户
	BashRunCommand("useradd -u 27 mysql -g mysql -M -s /sbin/nologin 2>/dev/null || true")
}

// ============ DownloadRpmMasterPackages (line 1705-1721) ============

func DownloadRpmMasterPackages() {
	logger_Printf("[下载] Master 节点 RPM 包...")

	var masterTar string
	if OSReleaseVersionB {
		masterTar = "http://mirror.cloud.idcsmart.com/cloud/packages/c7/rpms-master.tar.gz"
	} else if OSReleaseVersionL {
		masterTar = "http://mirror.cloud.idcsmart.com/cloud/packages/c8/rpms-master.tar.gz"
	}

	if masterTar != "" {
		DownloadFile(masterTar, "/home/zjmf/download/rpms-master.tar.gz")
		DeCompression("/home/zjmf/download/rpms-master.tar.gz", "/home/zjmf/download/")
	}
}

// ============ DownloadDockerPackages (line 1723-1750) ============

func DownloadDockerPackages() {
	logger_Printf("[下载] Docker/Podman 相关包...")

	var dockerTar string
	if OSReleaseVersionB {
		dockerTar = "http://mirror.cloud.idcsmart.com/cloud/packages/c7/rpms-docker.tar.gz"
	} else if OSReleaseVersionL {
		dockerTar = "http://mirror.cloud.idcsmart.com/cloud/packages/c8/rpms-docker.tar.gz"
	}

	if dockerTar != "" {
		DownloadFile(dockerTar, "/home/zjmf/download/rpms-docker.tar.gz")
		DeCompression("/home/zjmf/download/rpms-docker.tar.gz", "/home/zjmf/download/")
	}
}

// ============ DatabaseServiceCreate (line 1752-1758) ============

func DatabaseServiceCreate() {
	logger_Printf("[数据库] 创建 MariaDB 服务...")

	// 下载 MariaDB 5.5
	mariaDbUrl := fmt.Sprintf("%s/mariadb-5.5.tar.gz", DefaultRepo)
	DownloadFile(mariaDbUrl, "/home/zjmf/download/mariadb-5.5.tar.gz")
	DeCompression("/home/zjmf/download/mariadb-5.5.tar.gz", "/home/zjmf/")

	// 初始化数据库
	BashRunCommand("/home/zjmf/mariadb-5.5/scripts/mysql_install_db --user=mysql --basedir=/home/zjmf/mariadb-5.5 --datadir=/home/zjmf/database")

	// 启动 MariaDB
	BashRunCommand("/home/zjmf/mariadb-5.5/bin/mysqld_safe --datadir=/home/zjmf/database &")
	time.Sleep(5 * time.Second)

	// 设置 root 密码
	MysqlRootPassword = RandomString(16)
	MysqlCloudPassword = RandomString(16)

	BashRunCommand(fmt.Sprintf(
		"/home/zjmf/mariadb-5.5/bin/mysqladmin -u root password '%s'", MysqlRootPassword))

	// 创建 cloud 数据库用户
	BashRunCommand(fmt.Sprintf(
		"/home/zjmf/mariadb-5.5/bin/mysql -uroot -p%s -e 'grant all privileges on cloud.* to cloud@127.0.0.1 identified by \"%s\" with grant option;'",
		MysqlRootPassword, MysqlCloudPassword))

	BashRunCommand(fmt.Sprintf(
		"/home/zjmf/mariadb-5.5/bin/mysql -uroot -p%s -e 'grant all privileges on cloud.* to cloud@localhost identified by \"%s\" with grant option;'",
		MysqlRootPassword, MysqlCloudPassword))

	BashRunCommand(fmt.Sprintf(
		"/home/zjmf/mariadb-5.5/bin/mysql -uroot -p%s -e 'flush privileges;'",
		MysqlRootPassword))

	logger_Printf("[数据库] root密码: %s", MysqlRootPassword)
	logger_Printf("[数据库] cloud密码: %s", MysqlCloudPassword)
}


// ============ DockerDatabaseCreate (line 1760-1779) ============

func DockerDatabaseCreate() {
	logger_Printf("[Docker] 创建数据库容器...")

	// 创建数据卷
	BashRunCommand("mkdir -p /home/zjmf/share/zjmf-db")
	BashRunCommand(fmt.Sprintf(
		"curl -s http://mirror.cloud.idcsmart.com/cloud/docker/zjmf-db.tar.gz -o /home/zjmf/download/zjmf-db.tar.gz"))

	// Podman 导入数据库镜像
	BashRunCommand("podman import /home/zjmf/download/zjmf-db.tar.gz zjmf-db:latest")

	// 初始化数据库
	BashRunCommand(fmt.Sprintf(
		"podman run -d --name zjmf-db -v /home/zjmf/share/zjmf-db:/share zjmf-db:latest"))
}

// ============ DockerWebCreate (line 1781-1810) ============

func DockerWebCreate() {
	logger_Printf("[Docker] 创建 Web 容器...")

	version := InstallVersion
	webUrl := fmt.Sprintf("http://mirror.cloud.idcsmart.com/cloud/dashboard/%s/zjmf-web.tar.gz", version)
	DownloadFile(webUrl, "/home/zjmf/download/zjmf-web.tar.gz")

	// 导入镜像
	BashRunCommand("podman import /home/zjmf/download/zjmf-web.tar.gz zjmf-web:latest")

	// 启动容器
	logger_Printf("[Docker] 启动 zjmf-web 容器...")
	BashRunCommand(fmt.Sprintf(`podman run -d --name zjmf-web \
		-p 80:80 -p 443:443 -p 8443:8443 \
		-v /home/zjmf/share/zjmf-web/.env:/www/.env \
		-v /home/zjmf/share:/share \
		-v /home/zjmf/mariadb-5.5/data:/var/lib/mysql \
		zjmf-web:latest /usr/bin/supervisord`))
}

// ============ DockerCtlCreate (line 1812-1822) ============

func DockerCtlCreate() {
	logger_Printf("[Docker] 创建 Controller 容器...")

	version := InstallVersion
	ctlUrl := fmt.Sprintf("http://mirror.cloud.idcsmart.com/cloud/controller/%s/zjmf-ctl.tar.gz", version)
	DownloadFile(ctlUrl, "/home/zjmf/download/zjmf-ctl.tar.gz")

	BashRunCommand("podman import /home/zjmf/download/zjmf-ctl.tar.gz zjmf-ctl:latest")

	logger_Printf("[Docker] 启动 zjmf-ctl 容器...")
	BashRunCommand(fmt.Sprintf(`podman run -d --name zjmf-ctl \
		-p 8088:8088 \
		-v /home/zjmf/share/zjmf-ctl:/share/zjmf-ctl \
		-v /home/zjmf/share:/share \
		zjmf-ctl:latest /usr/bin/supervisord`))
}

// ============ DockerConfigAndInit (line 1824-1902) ============

func DockerConfigAndInit() {
	logger_Printf("[Docker] 配置和初始化容器环境...")

	// 等待容器启动
	time.Sleep(10 * time.Second)

	// 配置数据库
	logger_Printf("[Docker] 配置容器内数据库...")

	// 更新 DB 密码和配置
	sedCmd := fmt.Sprintf(
		"podman exec zjmf-ctl sh -c \"sed -i '/password=/ s/password=.*$/password=%s/g' /usr/local/zjmf/conf/zjmf.conf\"",
		MysqlRootPassword)
	BashRunCommand(sedCmd)

	sedCmd2 := fmt.Sprintf(
		"podman exec zjmf-ctl sh -c \"sed -i '/username=/ s/username=.*$/username=%s/g' /usr/local/zjmf/conf/zjmf.conf\"",
		CtlAuthUsername)
	BashRunCommand(sedCmd2)

	// 导入数据库 schema
	BashRunCommand(fmt.Sprintf(
		"podman exec zjmf-db sh -c \"exec mysql -uroot -p%s cloud < /share/zjmf-db/local_cloud.sql\"",
		MysqlRootPassword))

	// 更新 admin 密码
	BashRunCommand(fmt.Sprintf(
		"sed -i \"59 s/'admin', '.*', '/'admin', '%s', '/g\" /home/zjmf/share/zjmf-db/local_cloud.sql",
		WebAdminPassword))

	// 配置 area username/password
	BashRunCommand(fmt.Sprintf(
		"sed -i \"346 s/'local_area_password', '.*',/'local_area_password', '%s',/g\" /home/zjmf/share/zjmf-db/local_cloud.sql",
		CtlAuthPassword))

	BashRunCommand(fmt.Sprintf(
		"sed -i \"347 s/'local_area_username', '.*',/'local_area_username', '%s',/g\" /home/zjmf/share/zjmf-db/local_cloud.sql",
		CtlAuthUsername))

	// PHP 安装步骤
	logger_Printf("[初始化] 执行 Dashboard 安装脚本...")
	BashRunCommand("/usr/bin/php /home/zjmf/dashboard/www/think install_area")

	if LicenseRequest != nil {
		BashRunCommand(fmt.Sprintf("/usr/bin/php /home/zjmf/dashboard/www/think install_license %s", ZjmfLicense))
	}

	BashRunCommand(fmt.Sprintf("/usr/bin/php /home/zjmf/dashboard/www/think set_admin_path %s", WebAdminPath))
	BashRunCommand("/usr/bin/php /home/zjmf/dashboard/www/think restart_nginx '' 10")

	// 设置权限
	BashRunCommand("chown -R nginx:nginx /home/zjmf/dashboard")
	BashRunCommand("podman exec zjmf-ctl sh -c \"chown -R www-data:www-data /share\"")
	BashRunCommand("podman exec zjmf-web sh -c \"chown -R www-data:www-data /share\"")

	logger_Printf("[Docker] 容器配置完成")
}

// ============ InstallMasterConfig (line 1904-2165) ============

func InstallMasterConfig() {
	logger_Printf("[配置] Master 节点配置...")

	// 下载配置模板
	shareUrl := fmt.Sprintf("%s/share.tar.gz", DefaultRepo)
	DownloadFile(shareUrl, "/home/zjmf/download/share.tar.gz")
	DeCompression("/home/zjmf/download/share.tar.gz", "/home/zjmf/share/")

	// 配置 ovs / br0
	logger_Printf("[配置] 网络配置...")

	if LightNetworkMode {
		// 轻量模式使用 bridge
		logger_Printf("[配置] 配置 br0 bridge...")
		BashRunCommand("ovs-vsctl add-br ovsbr1 && ip link set ovsbr1 up")
		BashRunCommand(fmt.Sprintf(
			"sed -i \"s/%s/br0/g\" /etc/sysconfig/network-scripts/route-br0", ChoosesInterface))
	} else {
		// OVS 模式
		logger_Printf("[配置] 配置 OVS 网桥...")
		// ... OVS 配置逻辑在 ComputeOvsNetworkConfig
	}

	// 配置接口文件
	BashRunCommand(fmt.Sprintf(
		"sed -i '/DEVICE=/a\\DEVICETYPE=ovs' /etc/sysconfig/network-scripts/ifcfg-phy-ext"))

	// 启用系统服务
	logger_Printf("[配置] 启用系统服务...")
	BashRunCommand("systemctl stop NetworkManager && systemctl disable NetworkManager")
	BashRunCommand("systemctl restart aria2-node ryu-manager flowentryd influxdb")
	BashRunCommand("systemctl enable api-web crontab-web nginx80 nginx443 nginx8443")
	BashRunCommand("systemctl enable nginx-ctl api-ctl crontab-ctl websockify webssh")

	// 配置 sudoers
	logger_Printf("[配置] 配置 sudoers...")
	BashRunCommand(`echo "Cmnd_Alias CLOUD = /usr/bin/virsh, /usr/local/zjmf/cloud/kvm_mon_all.py, /usr/local/zjmf/cloud/controller.py, /usr/local/zjmf/cloud/qemu_agent.py, /usr/local/zjmf/cloud/volume.py, /usr/local/zjmf/cloud/network/network_service.py, /usr/local/zjmf/cloud/apps/tools" >> /etc/sudoers`)
	BashRunCommand(`echo "Cmnd_Alias ZJMF = /home/zjmf/dashboard/apps/cloudssl" >> /etc/sudoers`)

	// 更新模块配置
	BashRunCommand("echo 'options kvm_intel nested=1' >> /etc/modprobe.d/kvm-nested.conf")
	BashRunCommand("echo 'options kvm_intel ept=1' >> /etc/modprobe.d/kvm-nested.conf")

	logger_Printf("[配置] Master 配置完成")
}


// ============ InstallMasterService (line 2167-2284) ============

func InstallMasterService() {
	logger_Printf("[服务] 安装 Master 服务...")

	// 下载更新服务包
	updateUrl := fmt.Sprintf("%s/upgrade.tar.gz", DefaultRepo)
	DownloadFile(updateUrl, "/home/zjmf/download/upgrade.tar.gz")
	DeCompression("/home/zjmf/download/upgrade.tar.gz", "/home/zjmf/upgrade/")

	// 配置 supervisord
	logger_Printf("[服务] 配置 supervisord...")

	// aria2 配置
	BashRunCommand(`cat > /etc/supervisord.d/api-web.ini << 'EOF'
[program:api-web]
command=/home/zjmf/dashboard/apps/api-web
directory=/home/zjmf/dashboard/apps
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/api-web.log
stderr_logfile=/var/log/supervisor/api-web.err.log
EOF`)

	// crontab-web
	BashRunCommand(`cat > /etc/supervisord.d/crontab-web.ini << 'EOF'
[program:crontab-web]
command=/home/zjmf/bin/crontab -f /home/zjmf/dashboard/crontab-web.json
directory=/home/zjmf/dashboard
autostart=true
autorestart=true
EOF`)

	// websockify
	BashRunCommand(`cat > /etc/supervisord.d/websockify.ini << 'EOF'
[program:websockify]
command=/home/zjmf/controller/websockify/run --target-config /home/zjmf/controller/token 0.0.0.0:4451
directory=/home/zjmf/controller/websockify
autostart=true
autorestart=true
EOF`)

	logger_Printf("[服务] Master 服务安装完成")
}

// ============ InitializationMaster (line 2286-2357) ============

func InitializationMaster() {
	logger_Printf("[初始化] Master 节点初始化...")

	// 创建必要目录
	dirs := []string{
		"/home/zjmf/dashboard/www/public",
		"/home/zjmf/controller/www/public",
		"/home/zjmf/mariadb-5.5/data",
		"/home/zjmf/download",
		"/home/zjmf/upgrade",
	}

	for _, d := range dirs {
		BashRunCommand(fmt.Sprintf("mkdir -p %s", d))
	}

	// 设置权限
	BashRunCommand("chown -R mysql:mysql /home/zjmf/mariadb-5.5")

	logger_Printf("[初始化] Master 初始化完成")
}

// ============ DownloadRpmControllerPackages (line 2359-2376) ============

func DownloadRpmControllerPackages() {
	logger_Printf("[下载] Controller 包...")

	version := InstallVersion
	ctlUrl := fmt.Sprintf("http://mirror.cloud.idcsmart.com/cloud/controller/%s/zjmf-ctl.tar.gz", version)
	DownloadFile(ctlUrl, "/home/zjmf/download/zjmf-ctl.tar.gz")
}

// ============ InstallControllerShare (line 2383-2390) ============

func InstallControllerShare() {
	logger_Printf("[安装] Controller 共享配置...")

	BashRunCommand("mkdir -p /home/zjmf/share/zjmf-ctl")
	BashRunCommand("mkdir -p /home/zjmf/share/zjmf-web")
}

// ============ InstallControllerConfig (line 2392-2555) ============

func InstallControllerConfig() {
	logger_Printf("[配置] Controller 配置...")

	// 配置 zjmf.conf
	configContent := fmt.Sprintf(`[database]
mysql_root_password=%s
mysql_cloud_password=%s

[auth]
ctl_auth_username=%s
ctl_auth_password=%s

[license]
license=%s

[network]
interface=%s
`, MysqlRootPassword, MysqlCloudPassword, CtlAuthUsername, CtlAuthPassword, ZjmfLicense, ChoosesInterface)

	WriteConfig("/usr/local/zjmf/conf/zjmf.conf", map[string]string{
		"mysql_root_password":   MysqlRootPassword,
		"mysql_cloud_password":  MysqlCloudPassword,
		"ctl_auth_username":     CtlAuthUsername,
		"ctl_auth_password":     CtlAuthPassword,
		"zjmf_auth_code":        ZjmfLicense,
	})
	_ = configContent

	logger_Printf("[配置] Controller 配置完成")
}

// ============ InstallControllerService (line 2557-2637) ============

func InstallControllerService() {
	logger_Printf("[服务] 安装 Controller 服务...")

	BashRunCommand(`cat > /etc/supervisord.d/api-ctl.ini << 'EOF'
[program:api-ctl]
command=/home/zjmf/controller/apps/api-ctl
directory=/home/zjmf/controller/apps
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/api-ctl.log
stderr_logfile=/var/log/supervisor/api-ctl.err.log
EOF`)

	BashRunCommand(`cat > /etc/supervisord.d/crontab-ctl.ini << 'EOF'
[program:crontab-ctl]
command=/home/zjmf/bin/crontab -f /home/zjmf/controller/crontab-ctl.json
directory=/home/zjmf/controller
autostart=true
autorestart=true
EOF`)

	logger_Printf("[服务] Controller 服务安装完成")
}

// ============ InitializationController (line 2639-2659) ============

func InitializationController() {
	logger_Printf("[初始化] Controller 初始化...")

	// 解压 Controller 包
	BashRunCommand("podman exec zjmf-ctl sh -c \"mkdir -p /share/zjmf-ctl/ceph\"")

	// 下载 jq
	BashRunCommand(fmt.Sprintf(
		"curl -s http://mirror.cloud.idcsmart.com/cloud/software/bin/jq -o /usr/local/bin/jq && chmod +x /usr/local/bin/jq"))

	logger_Printf("[初始化] Controller 初始化完成")
}

// ============ DownloadAndInstallZJMF (line 2661-2668) ============

func DownloadAndInstallZJMF() {
	logger_Printf("[安装] ZJMF 核心组件...")

	// 下载 datapath.db
	dbUrl := "http://mirror.cloud.idcsmart.com/cloud/compute/datapath.db"
	DownloadFile(dbUrl, "/usr/local/zjmf/cloud/network/datapath.db")

	BashRunCommand("chmod +x /usr/local/zjmf/cloud/network/*.py")
	BashRunCommand("chown -R nginx:nginx /home/zjmf/controller")

	logger_Printf("[安装] ZJMF 核心组件安装完成")
}

// ============ DownloadAndInstallComputePackages (line 2727-2780) ============

func DownloadAndInstallComputePackages() {
	logger_Printf("[下载] Compute 节点包...")

	version := InstallVersion
	computeUrl := fmt.Sprintf("http://mirror.cloud.idcsmart.com/cloud/compute/%s.tar.gz", version)
	DownloadFile(computeUrl, "/home/zjmf/download/compute.tar.gz")
	DeCompression("/home/zjmf/download/compute.tar.gz", "/home/zjmf/download/")

	// 下载 python2/python3 包
	var py2Url, py3Url string
	if OSReleaseVersionB {
		py2Url = "http://mirror.cloud.idcsmart.com/cloud/packages/c7/python2-packages.tar.gz"
		py3Url = "http://mirror.cloud.idcsmart.com/cloud/packages/c7/python3-packages.tar.gz"
	} else if OSReleaseVersionL {
		py2Url = "http://mirror.cloud.idcsmart.com/cloud/packages/c8/python2-packages.tar.gz"
		py3Url = "http://mirror.cloud.idcsmart.com/cloud/packages/c8/python3-packages.tar.gz"
	}

	DownloadFile(py2Url, "/home/zjmf/download/python2-packages.tar.gz")
	DownloadFile(py3Url, "/home/zjmf/download/python3-packages.tar.gz")

	logger_Printf("[下载] Compute 包下载完成")
}


// ============ ComputeOvsNetworkConfig (line 2782-2865) ============

func ComputeOvsNetworkConfig() {
	logger_Printf("[网络] 配置 OVS 网络模式...")

	// 创建 OVS 网桥
	logger_Printf("[网络] 创建 OVS 网桥...")
	BashRunCommand("ovs-vsctl add-br ovs-ext")
	BashRunCommand("ovs-vsctl add-br ovs-int")
	BashRunCommand("ovs-vsctl add-br ovs-tun")
	BashRunCommand("ovs-vsctl add-br phy-ext")
	BashRunCommand("ovs-vsctl add-br phy-int")

	// 设置 datapath-id
	BashRunCommand("ovs-vsctl set Bridge ovs-ext other_config=disable-in-band=true,datapath-id=0000f01fafe06cb7")
	BashRunCommand("ovs-vsctl set Bridge ovs-int other_config=disable-in-band=true,datapath-id=0000be1b8f381446")
	BashRunCommand("ovs-vsctl set Bridge ovs-tun other_config=disable-in-band=true,datapath-id=0000fe9f17664a43")
	BashRunCommand("ovs-vsctl set Bridge phy-int other-config=disable-in-band=true,datapath-id=00006a8c71dd7548")
	BashRunCommand("ovs-vsctl set Bridge phy-ext other_config=disable-in-band=true,datapath-id=0000f01fafe06cb6")

	// 创建 patch port 连接
	logger_Printf("[网络] 创建 patch port 连接...")
	BashRunCommand("ovs-vsctl add-port ovs-ext oext-to-pext -- set interface oext-to-pext type=patch options:peer=pext-to-oext")
	BashRunCommand("ovs-vsctl add-port ovs-int oint-to-pint -- set interface oint-to-pint type=patch options:peer=pint-to-oint")
	BashRunCommand("ovs-vsctl add-port phy-ext pext-to-oext -- set interface pext-to-oext type=patch options:peer=oext-to-pext")
	BashRunCommand("ovs-vsctl add-port phy-int pint-to-oint -- set interface pint-to-oint type=patch options:peer=oint-to-pint")
	BashRunCommand("ovs-vsctl add-port ovs-ext oext-to-otun -- set interface oext-to-otun type=patch options:peer=otun-to-oext")
	BashRunCommand("ovs-vsctl add-port ovs-tun otun-to-oext -- set interface otun-to-oext type=patch options:peer=oext-to-otun")

	// 配置物理接口
	if ChoosesInterface != "" {
		BashRunCommand(fmt.Sprintf("ovs-vsctl add-port phy-ext %s", ChoosesInterface))
	}

	// 创建接口配置文件
	logger_Printf("[网络] 生成接口配置文件...")

	// ifcfg-ovs-ext
	BashRunCommand(`cat > /etc/sysconfig/network-scripts/ifcfg-ovs-ext << 'EOF'
DEVICE=ovs-ext
BOOTPROTO=none
ONBOOT=yes
DEVICETYPE=ovs
EOF`)

	// ifcfg-ovsbr1 或类似配置
	BashRunCommand(`cat > /etc/sysconfig/network-scripts/ifcfg-ovsbr1 << 'EOF'
DEVICE=ovsbr1
BOOTPROTO=none
ONBOOT=yes
EOF`)

	BashRunCommand("systemctl restart network")
	logger_Printf("[网络] OVS 配置完成")
}

// ============ ComputeBridgeNetworkConfig (line 2867-2915) ============

func ComputeBridgeNetworkConfig() {
	logger_Printf("[网络] 配置 Bridge 网络模式...")

	// 创建 Linux Bridge br0
	logger_Printf("[网络] 创建 br0 bridge...")
	BashRunCommand("brctl addbr br0 && ip link set br0 up")

	// 添加物理接口到 br0
	if ChoosesInterface != "" {
		BashRunCommand(fmt.Sprintf("brctl addif br0 %s", ChoosesInterface))
	}

	// 配置 ifcfg-bond (如果是 bond 模式)
	if ChoosesTrunkMode {
		BashRunCommand(`cat > /etc/sysconfig/network-scripts/ifcfg-bond0 << 'EOF'
DEVICE=bond0
BOOTPROTO=none
ONBOOT=yes
BONDING_OPTS="mode=802.3ad miimon=100"
EOF`)
	}

	// 配置 ifcfg-ovsbr1
	BashRunCommand(`cat > /etc/sysconfig/network-scripts/ifcfg-ovsbr1 << 'EOF'
DEVICE=ovsbr1
BOOTPROTO=none
ONBOOT=yes
DEVICETYPE=ovs
EOF`)

	// 配置 ifcfg-ifb0
	BashRunCommand(`cat > /etc/sysconfig/network-scripts/ifcfg-ifb0 << 'EOF'
DEVICE=ifb0
BOOTPROTO=none
ONBOOT=yes
EOF`)

	BashRunCommand("systemctl restart network")
	logger_Printf("[网络] Bridge 配置完成")
}

// ============ ConfigModuleLoads (line 2917-2938) ============

func ConfigModuleLoads() {
	logger_Printf("[模块] 配置内核模块...")

	// 配置 module 加载
	BashRunCommand(`cat > /etc/modules-load.d/ifb.conf << 'EOF'
ifb
EOF`)

	BashRunCommand(`cat > /etc/modprobe.d/ifb.conf << 'EOF'
options ifb numifbs=0
EOF`)

	BashRunCommand(`cat > /etc/modprobe.d/nbd.conf << 'EOF'
EOF`)

	// 加载模块
	BashRunCommand("modprobe ifb numifbs=0")
	BashRunCommand("modprobe br_netfilter")
	BashRunCommand("modprobe nbd max_part=8")

	// sysctl 配置
	BashRunCommand(`cat > /etc/sysctl.d/99-zjmf.conf << 'EOF'
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-arptables=1
EOF`)

	BashRunCommand("sysctl -p /etc/sysctl.d/99-zjmf.conf 2>/dev/null || true")
	logger_Printf("[模块] 内核模块配置完成")
}

// ============ InstallComputeConfig (line 2940-3100) ============

func InstallComputeConfig() {
	logger_Printf("[配置] Compute 节点配置...")

	// 创建配置目录
	BashRunCommand("mkdir -p /etc/supervisord.d")

	// 配置 libvirtd
	BashRunCommand(`cat > /etc/sysconfig/libvirtd << 'EOF'
LIBVIRTD_ARGS="--listen"
EOF`)

	BashRunCommand(`sed -i 's/#listen_tls = 0/listen_tls = 0/' /etc/libvirt/libvirtd.conf`)
	BashRunCommand(`sed -i 's/#listen_udp = 0/listen_udp = 0/' /etc/libvirt/libvirtd.conf`)
	BashRunCommand(`sed -i 's/#listen_addresses = "localhost"/listen_addresses = "0.0.0.0"/' /etc/libvirt/libvirtd.conf`)

	// 启用服务
	BashRunCommand("systemctl enable libvirtd-tcp.socket")
	BashRunCommand("systemctl restart libvirtd")

	// 配置 RYU SDN 控制器
	BashRunCommand(`cat > /etc/supervisord.d/ryu-manager.ini << 'EOF'
[program:ryu-manager]
command=/usr/bin/python2.7 /usr/bin/ryu-manager /usr/local/zjmf/cloud/network/switch.py /usr/lib/python2.7/site-packages/ryu/app/ofctl_rest.py --verbose --wsapi-host 127.0.0.1 --ofp-listen-host 127.0.0.1
directory=/usr/local/zjmf/cloud/network
autostart=true
autorestart=true
EOF`)

	// 配置 flowentryd
	BashRunCommand(`cat > /etc/supervisord.d/flowentryd.ini << 'EOF'
[program:flowentryd]
command=/usr/local/zjmf/cloud/apps/flowentryd
directory=/usr/local/zjmf/cloud/apps
autostart=true
autorestart=true
EOF`)

	// 配置 KSM
	BashRunCommand(`cat > /lib/systemd/system/ksmmgr.service << 'EOF'
[Unit]
Description=KSM Manager

[Service]
ExecStart=/usr/local/zjmf/bin/ksmtuned
WorkingDirectory=/usr/local/zjmf/bin
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF`)

	BashRunCommand("systemctl enable ksmmgr.service")

	logger_Printf("[配置] Compute 配置完成")
}

// ============ InstallComputeService (line 3102-3257) ============

func InstallComputeService() {
	logger_Printf("[服务] 安装 Compute 服务...")

	// 配置 updaemon_compute
	BashRunCommand(`cat > /etc/supervisord.d/updaemon-compute.ini << 'EOF'
[program:updaemon_compute]
command=/usr/local/zjmf/cloud/apps/updaemon_compute
directory=/usr/local/zjmf/cloud/apps
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/updaemon_compute.log
stderr_logfile=/var/log/supervisor/updaemon_compute.err.log
EOF`)

	// 配置 openvswitch
	BashRunCommand("systemctl enable openvswitch")
	BashRunCommand("systemctl restart openvswitch")

	logger_Printf("[服务] Compute 服务安装完成")
}

// ============ InitializationCompute (line 3259-3342) ============

func InitializationCompute() {
	logger_Printf("[初始化] Compute 节点初始化...")

	// 下载 compute 包
	computeUrl := fmt.Sprintf("http://mirror.cloud.idcsmart.com/cloud/compute/%s.tar.gz", InstallVersion)
	DownloadFile(computeUrl, "/home/zjmf/download/compute.tar.gz")

	// 创建基础目录
	BashRunCommand("mkdir -p /usr/local/zjmf/cloud/network")
	BashRunCommand("mkdir -p /home/zjmf/images")
	BashRunCommand("mkdir -p /home/zjmf/download/compute")

	// 下载 datapath.db
	BashRunCommand(fmt.Sprintf(
		"curl -s http://mirror.cloud.idcsmart.com/cloud/compute/datapath.db -o /usr/local/zjmf/cloud/network/datapath.db"))

	// 设置权限
	BashRunCommand("chmod +x /usr/local/zjmf/cloud/network/*.py")
	BashRunCommand("chmod 755 /home/kvm/images")

	logger_Printf("[初始化] Compute 初始化完成")
}


// ============ ParseParameter (line 3443-3454) ============

func ParseParameter() {
	flag.StringVar(&InstallArea, "area", "CN", "area mod")
	flag.StringVar(&SpecifiedVersion, "version", "", "target version")
	flag.StringVar(&ZjmfLicense, "license", "", "license")
	flag.StringVar(&LogFileName, "log", "", "log file path.")
	flag.StringVar(&WebAdminPath, "webpath", "", "web admin path")
	flag.BoolVar(&OnlyInstallController, "onlyctl", false, "target version")
	flag.BoolVar(&LightNetworkMode, "l", false, "LightNetworkMode")
	flag.BoolVar(&ChoosesTrunkMode, "t", false, "trunkmode")
	flag.BoolVar(&SkipKernelCheck, "nokernel", false, "no check kernel")
	flag.BoolVar(&DefaultRepoBool, "norepo", false, "norepo")

	flag.Parse()
}

// DefaultRepoBool 临时变量用于 flag
var DefaultRepoBool bool

// ============ main.main (line 3456-3978) ============

func main() {
	// === 初始化阶段 ===
	logger_Println("# ================= [ idcsmart ] =========================== #")
	logger_Println("# ", time.Now().Format("2006-01-02 15:04:05"))

	// 解析命令行参数
	ParseParameter()

	// 设置日志文件名（带时间戳）
	if LogFileName == "" {
		LogFileName = fmt.Sprintf("/tmp/zjmf-cloud-install-%s.log",
			time.Now().Format("20060102-150405"))
	}

	logger_Printf("[日志] 日志文件: %s", LogFileName)

	// 检查日志文件是否存在
	if CheckFileStatus(LogFileName) {
		logger_Println("[信息] 检测到已有安装记录，尝试恢复配置...")

		// 读取已保存的配置
		config, _ := InitConfig(LogFileName)
		MysqlRootPassword = config["mysql_root_password"]
		MysqlCloudPassword = config["mysql_cloud_password"]
		WebAdminPath = config["web_admin_path"]
		WebAdminPassword = config["web_admin_password"]
		CtlAuthUsername = config["ctl_auth_username"]
		CtlAuthPassword = config["ctl_auth_password"]
		ZjmfLicense = config["license"]

		logger_Println("[信息] 配置已恢复")
	}

	StartTime = time.Now()
	logger_Println("[开始] ZJMF Cloud 安装程序启动")
	logger_Println("[时间] 开始时间:", StartTime.Format("2006-01-02 15:04:05"))

	// === 安装类型选择 ===
	if OnlyInstallController {
		logger_Println("[模式] 仅安装 Controller 模式")
		ChooseInstallType = 222 // 特殊值
	} else if SpecifiedVersion != "" {
		ChooseInstallType = 1 // 用户指定版本，跳过交互式选择

		logger_Println("====================== 安装类型选择 ======================")
		logger_Println("指定了安装版本，跳过交互式选择")
	} else {
		// 交互式选择
		for {
			logger_Println("# ================= [ idcsmart ] =========================== #")
			logger_Println("# ")
			logger_Println("# 感谢您使用智简魔方云系统安装程序 V2")
			logger_Println("# http://www.idcsmart.com")
			logger_Println("# ")
			logger_Println("# ================= [ 请选择将要安装的系统 ] ================= #")
			logger_Println("# ")
			logger_Println("# [1] 仅安装WEBUI, 主控管理面板.")
			logger_Println("# [2] 仅安装计算节点.")
			logger_Println("# [3] 同时安装WEBUI主控和计算节点.")
			logger_Println("# ")
			logger_Println("# ========================================================== #")

			var choice int
			fmt.Print("请选择将要安装的系统: ")
			fmt.Scan(&choice)

			switch choice {
			case 1:
				ChooseInstallType = 1
				logger_Println("[选择] 仅安装 Controller + Web")
				goto MainInstallation
			case 2:
				ChooseInstallType = 2
				logger_Println("[选择] 仅安装 Compute 节点")
				goto MainInstallation
			case 3:
				ChooseInstallType = 3
				logger_Println("[选择] 同时安装 Controller 和 Compute")
				goto MainInstallation
			default:
				logger_Println("输入错误,请重新输入正确的序号...")
			}
		}
	}

MainInstallation:
	// === 环境检查阶段 ===
	logger_Println("\n====================== [环境检查] ======================")

	CheckSystemRelease()
	CheckSElinux()
	CheckKernelVersion()
	CheckNetwork()
	CheckRootSpaces()
	CheckHomeSpaces()

	// 检查环境状态
	envChecks := []bool{
		OSReleaseVersionStatus,
		CheckSElinuxStatus,
		LinuxKernelVersionStatus,
		NetworkStatus,
		RootFreeSpacesStatus,
	}

	passed := 0
	for _, c := range envChecks {
		if c {
			passed++
		}
	}

	if passed < len(envChecks) {
		logger_Printf("[警告] %d/%d 项检查通过，某些检查未通过但将继续安装",
			passed, len(envChecks))
	} else {
		logger_Println("[检查] 所有环境检查通过")
	}

	// === 许可证检查 ===
	logger_Println("\n====================== [许可证] ======================")

	if ZjmfLicense == "" {
		logger_Println("[提示] 未提供 License 信息")
		logger_Println("如需获取 License，请访问: http://www.idcsmart.com")
	} else {
		logger_Printf("[License] 正在验证 License...")
		CheckLicense()
	}

	// === 网卡选择 ===
	logger_Println("\n====================== [网络接口] ======================")

	// 获取本机 IP
	LocalIPaddress = strings.Join(ListAllLocalIpAddress(), ",")

	// 获取外网 IP
	extIP, err := RunCommandOutput("curl", "-s", "--connect-timeout", "5",
		"http://154.7.178.154/app/api/ip")
	if err == nil {
		ExternalIPaddress = strings.TrimSpace(extIP)
	} else {
		ExternalIPaddress = LocalIPaddress
	}

	logger_Printf("[IP] 内网 IP: %s", LocalIPaddress)
	logger_Printf("[IP] 外网 IP: %s", ExternalIPaddress)

	ChooseComputeNetworkInterface()

	if ChoosesInterface == "" {
		logger_Println("[提示] 未指定网卡，使用默认配置")
	}

	// === 版本选择 ===
	logger_Println("\n====================== [版本选择] ======================")

	SelectVersion()

	if LightNetworkMode {
		logger_Println("[模式] 轻量网络模式 (不使用 OVS)")
	} else {
		logger_Println("[模式] OVS 网络模式")
	}

	// === 安装配置收集 ===
	logger_Println("\n====================== [安装配置] ======================")

	CollectMasterInstallConfig()
	CollectControllerInstallConfig()
	CollectComputeInstallConfig()
	CollectComputeNerworkModeConfig()

	// 生成随机密码
	if WebAdminPath == "" {
		WebAdminPath = RandomString(8)
	}
	WebAdminPassword = RandomString(16)
	CtlAuthUsername = "admin"
	CtlAuthPassword = RandomString(16)

	// 保存配置到日志文件
	logger_Printf("[保存配置] 写入安装日志: %s", LogFileName)
	configMap := map[string]string{
		"mysql_root_password":   MysqlRootPassword,
		"mysql_cloud_password":  MysqlCloudPassword,
		"web_admin_path":        WebAdminPath,
		"web_admin_password":    WebAdminPassword,
		"ctl_auth_username":     CtlAuthUsername,
		"ctl_auth_password":     CtlAuthPassword,
		"license":              ZjmfLicense,
		"install_version":       InstallVersion,
		"interface":             ChoosesInterface,
		"os_release":            strconv.Itoa(OSReleaseVersionNum),
	}
	WriteConfig(LogFileName, configMap)

	logger_Println("\n====================== [开始安装] ======================\n")

	// === 根据安装类型执行不同流程 ===
	switch ChooseInstallType {
	case 1: // 仅 Controller/Web
		installControllerOnly()
	case 2: // 仅 Compute
		installComputeOnly()
	case 3: // Controller + Compute
		installAll()
	case 222: // onlyctl 参数模式
		installControllerOnly()
	}

	// === 安装完成 ===
	endTime := time.Now()
	duration := endTime.Sub(StartTime)

	logger_Println("\n====================== [安装完成] ======================")
	logger_Println("[时间] 完成时间:", endTime.Format("2006-01-02 15:04:05"))
	logger_Printf("[耗时] %v\n", duration)
	logger_Println("==========================================================")

	if ChooseInstallType != 2 {
		logger_Println("")
		logger_Printf("请保存以下重要信息:\n")
		logger_Printf("  WebUI 访问地址: https://<服务器IP>/%s\n", WebAdminPath)
		logger_Printf("  WebUI 密码:     %s\n", WebAdminPassword)
		logger_Printf("  数据库 root 密码: %s\n", MysqlRootPassword)
		logger_Printf("  数据库 cloud 密码: %s\n", MysqlCloudPassword)
		logger_Println("")
		logger_Println("安装配置已保存在:", LogFileName)
		logger_Println("建议立即重启服务器以确保所有配置生效")
	}

	logger_Println("\n感谢使用智简魔方云系统!")
	logger_Println("访问 http://www.idcsmart.com 获取更多支持")
}

// ============ 安装流程函数 ============

func installControllerOnly() {
	logger_Println("[安装] Controller + Web 安装流程")

	InitializationMaster()
	InitializationPublicService()
	DownloadAndInstallPublicPackages()
	DownloadRpmMasterPackages()
	DownloadDockerPackages()

	DatabaseServiceCreate()
	DockerDatabaseCreate()
	DockerWebCreate()
	DockerCtlCreate()
	DockerConfigAndInit()

	InstallMasterConfig()
	InstallControllerConfig()
	InstallControllerShare()

	DownloadRpmControllerPackages()
	InitializationController()

	InstallMasterService()
	InstallControllerService()
	InstallPublicService()
}

func installComputeOnly() {
	logger_Println("[安装] Compute 安装流程")

	InitializationCompute()
	ConfigModuleLoads()

	DownloadAndInstallComputePackages()
	DownloadAndInstallPublicPackages()

	if LightNetworkMode {
		ComputeBridgeNetworkConfig()
	} else {
		ComputeOvsNetworkConfig()
	}

	InstallComputeConfig()
	InstallComputeService()
}

func installAll() {
	logger_Println("[安装] Controller + Compute 完整安装流程")

	// 先安装 Master/Controller
	InitializationMaster()
	InitializationPublicService()
	DownloadAndInstallPublicPackages()
	DownloadRpmMasterPackages()
	DownloadDockerPackages()

	DatabaseServiceCreate()
	DockerDatabaseCreate()
	DockerWebCreate()
	DockerCtlCreate()
	DockerConfigAndInit()

	InstallMasterConfig()
	InstallControllerConfig()
	InstallControllerShare()

	DownloadRpmControllerPackages()
	InitializationController()

	InstallMasterService()
	InstallControllerService()
	InstallPublicService()

	// 再安装 Compute
	logger_Println("\n====================== [Compute 节点] ======================\n")

	InitializationCompute()
	ConfigModuleLoads()

	DownloadAndInstallComputePackages()

	if LightNetworkMode {
		ComputeBridgeNetworkConfig()
	} else {
		ComputeOvsNetworkConfig()
	}

	InstallComputeConfig()
	InstallComputeService()
}

