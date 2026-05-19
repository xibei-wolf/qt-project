// ============================================================================
// NetworkClient.cpp — 青云志愿服务队管理系统 · 网络客户端实现
//
// TCP 粘包/半包处理策略：
//
//   粘包（Sticky Packet）：
//     一个 readyRead 信号携带多个完整报文。
//     → while 循环反复 tryExtractPacket()，直到可读数据不足。
//
//   半包（Half Packet / Fragmentation）：
//     一个报文跨 TCP 分段到达。
//     → m_nextBlockSize 记录预期的 Body 长度，数据不足时 return 挂起，
//       等待下一次 readyRead 信号继续读取。
//
// 状态机：
//   m_nextBlockSize == 0  →  等待读取 4 字节 Header
//   m_nextBlockSize >  0  →  等待读取 m_nextBlockSize 字节 Body
//
// 与 Linux Muduo 服务端的字节序一致性：
//   本端写入: QDataStream + BigEndian → 网络字节序（大端）
//   对端读取: ntohl() → 主机字节序
//   信号触发：responseReceived(action, data) → QML slot
// ============================================================================

#include "NetworkClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

// ============================================================================
// 单例实现
// ============================================================================

NetworkClient* NetworkClient::instance()
{
    static NetworkClient s_instance;
    return &s_instance;
}

// ============================================================================
// 构造 / 析构
// ============================================================================

NetworkClient::NetworkClient(QObject* parent)
    : QObject(parent)
    , m_socket(new QTcpSocket(this))
    , m_connectTimer(new QTimer(this))
{
    // ---------- 连接信号 → 内部槽 ----------
    connect(m_socket, &QTcpSocket::connected,
            this, &NetworkClient::slotConnected);

    // Qt 6 使用 errorOccurred 取代 Qt 5 的 error() 信号
    connect(m_socket, &QTcpSocket::errorOccurred,
            this, &NetworkClient::slotErrorOccurred);

    connect(m_socket, &QTcpSocket::disconnected,
            this, &NetworkClient::slotDisconnected);

    connect(m_socket, &QTcpSocket::readyRead,
            this, &NetworkClient::slotReadyRead);

    // ---------- 连接超时定时器 ----------
    m_connectTimer->setSingleShot(true);
    connect(m_connectTimer, &QTimer::timeout,
            this, &NetworkClient::slotConnectTimeout);
}

NetworkClient::~NetworkClient()
{
    if (m_socket->state() == QAbstractSocket::ConnectedState) {
        m_socket->disconnectFromHost();
    }
}

// ============================================================================
// QML 可调用槽
// ============================================================================

void NetworkClient::connectToServer(const QString& ip, quint16 port)
{
    // 若已连接到相同地址，忽略重复请求
    if (m_connected && m_remoteHost == ip && m_remotePort == port) {
        qDebug() << "[NetworkClient] Already connected to" << ip << port;
        return;
    }

    // 若当前有连接，先断开
    if (m_socket->state() != QAbstractSocket::UnconnectedState) {
        qDebug() << "[NetworkClient] Disconnecting from previous host...";
        m_socket->abort();  // 立即中止（不等握手完成）
    }

    // 重置解包状态机
    m_nextBlockSize = 0;
    m_readBuffer.clear();

    // 记录目标地址
    m_remoteHost = ip;
    m_remotePort = port;

    qDebug() << "[NetworkClient] Connecting to" << ip << port << "...";

    // 发起异步连接
    m_socket->connectToHost(ip, port);

    // 启动连接超时定时器
    m_connectTimer->start(kConnectTimeoutMs);
}

void NetworkClient::disconnectFromServer()
{
    if (m_socket->state() == QAbstractSocket::ConnectedState) {
        m_socket->disconnectFromHost();
    }
    // 若正在连接中，直接中止
    if (m_socket->state() == QAbstractSocket::ConnectingState) {
        m_socket->abort();
    }
}

// ============================================================================
// sendRequest — 封包发送
//
// 封包流程：
//   1. 将 action 注入 JSON Body（保证服务端路由可用）
//   2. JSON → QByteArray (Compact 格式，无多余空白)
//   3. 构建 [4B BigEndian len][JSON bytes]
//   4. 写入 socket
//
// 协议示例（发送 LOGIN 请求）：
//   Header:  00 00 00 37                          (0x37 = 55 字节)
//   Body:    {"action":"LOGIN","student_id":"2021001","password":"hash"}
// ============================================================================

void NetworkClient::sendRequest(const QString&    action,
                                const QJsonObject& body)
{
    if (!m_connected) {
        qWarning() << "[NetworkClient] sendRequest failed: not connected";
        emit connectionError(QStringLiteral("未连接到服务器"));
        return;
    }

    // 第 1 步：构建完整 JSON
    QJsonObject fullJson = body;
    fullJson[QStringLiteral("action")] = action;

    QJsonDocument doc(fullJson);
    QByteArray jsonBytes = doc.toJson(QJsonDocument::Compact);

    if (jsonBytes.size() > static_cast<int>(kMaxBodyLen)) {
        qWarning() << "[NetworkClient] Request too large:" << jsonBytes.size() << "bytes";
        emit connectionError(QStringLiteral("请求报文过大"));
        return;
    }

    // 第 2 步：构建网络字节序 Header
    QByteArray packet;
    {
        QDataStream stream(&packet, QIODevice::WriteOnly);
        stream.setByteOrder(QDataStream::BigEndian);
        // 写入 4 字节大端 uint32_t Body 长度
        stream << static_cast<quint32>(jsonBytes.size());
    }
    // 第 3 步：拼接 Body
    packet.append(jsonBytes);

    // 第 4 步：写入 TCP 发送缓冲区
    qint64 written = m_socket->write(packet);
    if (written != packet.size()) {
        qWarning() << "[NetworkClient] write incomplete:"
                   << written << "/" << packet.size();
    } else {
        qDebug() << "[NetworkClient] Sent" << action
                 << "—" << jsonBytes.size() << "bytes";
    }
}

// ============================================================================
// 属性访问
// ============================================================================

bool NetworkClient::isConnected() const
{
    return m_connected;
}

QString NetworkClient::remoteAddress() const
{
    if (m_connected) {
        return QStringLiteral("%1:%2").arg(m_remoteHost).arg(m_remotePort);
    }
    return {};
}

// ============================================================================
// 内部连接状态管理
// ============================================================================

void NetworkClient::setConnected(bool connected)
{
    if (m_connected != connected) {
        m_connected = connected;
        emit connectedChanged(m_connected);
    }
}

// ============================================================================
// slotConnected — TCP 三次握手完成
// ============================================================================

void NetworkClient::slotConnected()
{
    m_connectTimer->stop();

    m_remoteHost = m_socket->peerAddress().toString();
    m_remotePort = m_socket->peerPort();

    qDebug() << "[NetworkClient] Connected to" << m_remoteHost << m_remotePort;

    setConnected(true);
}

// ============================================================================
// slotDisconnected — 对端关闭或主动断开
// ============================================================================

void NetworkClient::slotDisconnected()
{
    m_connectTimer->stop();

    qDebug() << "[NetworkClient] Disconnected from" << m_remoteHost;

    // 重置解包状态机（防止残留状态影响下次连接）
    m_nextBlockSize = 0;
    m_readBuffer.clear();

    setConnected(false);
}

// ============================================================================
// slotConnectTimeout — 连接超时
// ============================================================================

void NetworkClient::slotConnectTimeout()
{
    qWarning() << "[NetworkClient] Connection timeout to"
               << m_remoteHost << m_remotePort;

    m_socket->abort();  // 触发 slotDisconnected + slotErrorOccurred

    emit connectionError(
        QStringLiteral("连接超时：无法连接到 %1:%2")
            .arg(m_remoteHost)
            .arg(m_remotePort));
}

// ============================================================================
// slotReadyRead — TCP 粘包/半包处理核心
//
// 【核心逻辑】
//   本槽函数由 QTcpSocket::readyRead 信号触发，运行在主线程事件循环中。
//   QTcpSocket 内置的读取缓冲区已经接收了 TCP 字节流，我们使用 m_nextBlockSize
//   作为简易状态机来决定当前是应该读取 Header 还是 Body。
//
// 【状态机流程】
//   ┌──────────────┐      bytesAvailable >= 4      ┌──────────────┐
//   │ WAIT_HEADER   │ ─────────────────────────►    │ WAIT_BODY    │
//   │ m_next=0      │                               │ m_next=N     │
//   └──────┬────────┘                               └──────┬───────┘
//          │  bytesAvailable < 4                          │ bytesAvailable >= N
//          ▼  (return)                                    ▼
//       [等待下次                                          读取 N 字节 Body
//        readyRead]                                        → 解析 JSON
//                                                          → 发射信号
//                                                          → m_next = 0 (回到 WAIT_HEADER)
//
// 【粘包】while 循环保证连续解出多个报文
// 【半包】return 挂起，QTcpSocket 内部缓冲区保留未完成数据
// ============================================================================

void NetworkClient::slotReadyRead()
{
    // 将新到达的数据追加到本地缓冲区
    QByteArray newData = m_socket->readAll();
    m_readBuffer.append(newData);

    // ================================================================
    // 循环解包 —— 一次处理缓冲区中所有完整报文
    // ================================================================
    while (true) {
        // ---------- 状态 1：等待 / 解析 Header（4 字节大端长度）----------
        if (m_nextBlockSize == 0) {
            // Header 不完整 → 挂起等待更多数据
            if (m_readBuffer.size() < kHeaderSize) {
                return;
            }

            // 从缓冲区头部解析 4 字节大端 uint32_t
            QDataStream stream(m_readBuffer.left(kHeaderSize));
            stream.setByteOrder(QDataStream::BigEndian);
            stream >> m_nextBlockSize;

            // 移除已消费的 Header
            m_readBuffer.remove(0, kHeaderSize);

            // 合法性校验
            if (m_nextBlockSize == 0) {
                // 空 Body 报文（合法，如心跳响应）
                // 直接视为一条完整报文，触发分发
                processEmptyPacket();
                continue;  // 继续循环，可能后续还有粘包数据
            }

            if (m_nextBlockSize > kMaxBodyLen) {
                // 协议异常：Body 长度超出上限。
                // 无法确定后续数据的对齐边界 → 清空缓冲区并断开连接。
                qWarning() << "[NetworkClient] Protocol error: bodyLen"
                           << m_nextBlockSize << "exceeds max"
                           << kMaxBodyLen;
                m_readBuffer.clear();
                m_nextBlockSize = 0;
                m_socket->abort();
                emit connectionError(
                    QStringLiteral("协议错误：报文长度 %1 超出上限").arg(m_nextBlockSize));
                return;
            }
        }

        // ---------- 状态 2：等待 Body 完整到达 ----------
        // m_nextBlockSize > 0 且 m_readBuffer 可能仍不足
        if (static_cast<quint32>(m_readBuffer.size()) < m_nextBlockSize) {
            // 半包：Body 尚未完全到达 → 保留 m_nextBlockSize 和 m_readBuffer，
            //       等待下次 readyRead 追加数据后继续读取
            return;
        }

        // ---------- Body 完整到达，切出 JSON ----------
        QByteArray jsonData = m_readBuffer.left(m_nextBlockSize);
        m_readBuffer.remove(0, m_nextBlockSize);
        m_nextBlockSize = 0;   // 重置状态机 → 回到 WAIT_HEADER

        // ---------- 解析 JSON 并发射信号 ----------
        processJsonPacket(jsonData);

        // 继续循环：检查 m_readBuffer 中是否还有粘包数据
    }
}

// ============================================================================
// 内部辅助方法
// ============================================================================

void NetworkClient::processEmptyPacket()
{
    // 空 Body 报文（心跳等）→ 发射空响应通知 QML
    qDebug() << "[NetworkClient] Received empty body packet (heartbeat)";
    emit responseReceived(QStringLiteral("heartbeat"), QJsonObject());
}

void NetworkClient::processJsonPacket(const QByteArray& jsonData)
{
    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(jsonData, &parseError);

    if (parseError.error != QJsonParseError::NoError) {
        qWarning() << "[NetworkClient] JSON parse error:"
                   << parseError.errorString()
                   << "at offset" << parseError.offset;
        emit connectionError(
            QStringLiteral("JSON 解析错误: %1").arg(parseError.errorString()));
        return;
    }

    if (!doc.isObject()) {
        qWarning() << "[NetworkClient] JSON is not an object";
        return;
    }

    QJsonObject obj = doc.object();

    // 提取标识字段：优先 action，其次 status
    QString action = obj.value(QStringLiteral("action")).toString();
    if (action.isEmpty()) {
        action = obj.value(QStringLiteral("status")).toString();
    }

    qDebug() << "[NetworkClient] Response received:"
             << "action/status =" << action
             << "size =" << jsonData.size() << "bytes";

    emit responseReceived(action, obj);
}

// ============================================================================
// slotErrorOccurred — 套接字异常处理（Qt 6）
// ============================================================================

void NetworkClient::slotErrorOccurred(QAbstractSocket::SocketError error)
{
    Q_UNUSED(error)

    QString errorMsg = m_socket->errorString();

    qWarning() << "[NetworkClient] Socket error:" << errorMsg;

    m_connectTimer->stop();

    // 仅当非正常断开时才通知 UI
    if (m_socket->state() != QAbstractSocket::ConnectedState) {
        setConnected(false);
    }

    emit connectionError(QStringLiteral("网络错误: %1").arg(errorMsg));
}
