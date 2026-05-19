// ============================================================================
// NetworkClient.h — 青云志愿服务队管理系统 · 跨平台网络客户端单例
//
// 职责：
//   1. 基于 QTcpSocket 的非阻塞长连接管理
//   2. 自定义协议封包/解包（4B 大端 Header + JSON Body）
//   3. TCP 粘包/半包的安全处理
//   4. 通过信号/属性无缝暴露给 QML 层
//
// 协议格式（与 Linux Muduo 服务端一致）：
//   ┌──────────────────┬───────────────────────────────┐
//   │ uint32_t bodyLen  │  JSON Body (UTF-8)            │
//   │ (4B, Big-Endian)  │  (bodyLen 字节)               │
//   └──────────────────┴───────────────────────────────┘
// ============================================================================

#pragma once

#include <QObject>
#include <QJsonObject>
#include <QJsonDocument>
#include <QTcpSocket>
#include <QDataStream>
#include <QTimer>
#include <QAbstractSocket>

// ============================================================================
// NetworkClient — 网络通信单例
//
// QML 使用示例：
//   NetworkClient.connectToServer("192.168.1.100", 8080)
//   NetworkClient.sendRequest("LOGIN", {"student_id": "2021001", "password": "xxx"})
//   Connections { target: NetworkClient; onResponseReceived: { ... } }
// ============================================================================

class NetworkClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged FINAL)

public:
    // ------------------------------------------------------------------
    // 单例接口
    // ------------------------------------------------------------------

    /// 获取全局唯一实例（C++11 线程安全 Meyers Singleton）
    static NetworkClient* instance();

    /// 禁止外部构造 / 拷贝
    NetworkClient(const NetworkClient&) = delete;
    NetworkClient& operator=(const NetworkClient&) = delete;

    // ------------------------------------------------------------------
    // QML 可调用槽
    // ------------------------------------------------------------------

    /// 连接到远程 Muduo 服务端
    /// @param ip   IPv4 地址，如 "192.168.80.128"
    /// @param port 服务端口，如 8080
    Q_INVOKABLE void connectToServer(const QString& ip, quint16 port);

    /// 主动断开连接
    Q_INVOKABLE void disconnectFromServer();

    /// 发送 JSON 请求报文（自动封包：action 注入 + Header 拼装）
    /// @param action 业务动作标识，如 "LOGIN"、"FILTER_AVAILABLE_MEMBERS"
    /// @param body   请求体 JSON，可省略（空对象）
    ///
    /// QML 调用示例：
    ///   NetworkClient.sendRequest("UPLOAD_SCHEDULE", {
    ///       "courses": [...]
    ///   })
    Q_INVOKABLE void sendRequest(const QString&    action,
                                 const QJsonObject& body = QJsonObject());

    // ------------------------------------------------------------------
    // 属性访问
    // ------------------------------------------------------------------

    /// 当前 TCP 连接状态
    bool isConnected() const;

    /// 当前连接的远端地址（含端口），未连接时为空
    QString remoteAddress() const;

signals:
    // ------------------------------------------------------------------
    // QML 交互信号
    // ------------------------------------------------------------------

    /// 连接状态变化（驱动 QML Property Binding）
    void connectedChanged(bool connected);

    /// 服务器返回的完整 JSON 响应
    /// @param action 服务端回传的 action 字段（如存在），否则为 status 字段
    /// @param data   完整 JSON 响应对象，QML 可通过 data.fieldName 直接访问
    void responseReceived(const QString&    action,
                          const QJsonObject& data);

    /// 网络错误通知（含中英文描述，可直接在 UI 上展示）
    void connectionError(const QString& errorString);

private slots:
    // ------------------------------------------------------------------
    // QTcpSocket 底层槽（内部使用，不导出给 QML）
    // ------------------------------------------------------------------

    /// 连接建立成功
    void slotConnected();

    /// 连接断开（主动或被动）
    void slotDisconnected();

    /// 数据到达 —— TCP 粘包/半包处理核心
    void slotReadyRead();

    /// 套接字错误处理
    void slotErrorOccurred(QAbstractSocket::SocketError error);

    /// 连接超时处理
    void slotConnectTimeout();

private:
    // ------------------------------------------------------------------
    // 构造 / 析构（私有，单例模式）
    // ------------------------------------------------------------------
    explicit NetworkClient(QObject* parent = nullptr);
    ~NetworkClient() override;

    // ------------------------------------------------------------------
    // 内部工具
    // ------------------------------------------------------------------

    /// 设置连接状态并发出通知
    void setConnected(bool connected);

    /// 处理空 Body 报文（心跳等）
    void processEmptyPacket();

    /// 解析 JSON 字节数组并发射 responseReceived 信号
    void processJsonPacket(const QByteArray& jsonData);

    // ------------------------------------------------------------------
    // 数据成员
    // ------------------------------------------------------------------
    QTcpSocket* m_socket       = nullptr;   // TCP 套接字（不拥有线程亲和性锁定）
    QTimer*     m_connectTimer = nullptr;   // 连接超时定时器

    // 粘包/半包解包状态机
    quint32     m_nextBlockSize = 0;         // 当前等待的 Body 字节数（0=等待Header）
    QByteArray  m_readBuffer;               // 未完成读取的缓冲数据

    // 连接状态
    bool        m_connected     = false;
    QString     m_remoteHost;              // 最后一次连接的远端地址（用于日志/重连）
    quint16     m_remotePort    = 0;

    // 协议常量
    static constexpr int    kHeaderSize   = 4;                   // sizeof(uint32_t)
    static constexpr int    kConnectTimeoutMs = 5000;            // 连接超时（毫秒）
    static constexpr quint32 kMaxBodyLen   = 4 * 1024 * 1024;    // 4 MB 上限
};
