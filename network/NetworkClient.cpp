// ============================================================================
// NetworkClient.cpp — 青云志愿服务队管理系统 · 网络客户端实现
//
// 非对称网关协议：
//
//   【上行】客户端 → 服务端：4B 大端长度头 + JSON Body
//          后端 tryExtractPacket 严格解析 4 字节大端长度头。
//
//   【下行】服务端 → 客户端：纯明文裸流 JSON
//          后端 sendResponse 直接吐出裸 JSON，无任何头部封装。
// ============================================================================

#include "NetworkClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <QFile>
#include <QStringDecoder>

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
    connect(m_socket, &QTcpSocket::connected,
            this, &NetworkClient::slotConnected);

    connect(m_socket, &QTcpSocket::errorOccurred,
            this, &NetworkClient::slotErrorOccurred);

    connect(m_socket, &QTcpSocket::disconnected,
            this, &NetworkClient::slotDisconnected);

    connect(m_socket, &QTcpSocket::readyRead,
            this, &NetworkClient::slotReadyRead);

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
    if (m_connected && m_remoteHost == ip && m_remotePort == port) {
        qDebug() << "[NetworkClient] Already connected to" << ip << port;
        return;
    }

    if (m_socket->state() != QAbstractSocket::UnconnectedState) {
        qDebug() << "[NetworkClient] Disconnecting from previous host...";
        m_socket->abort();
    }

    m_readBuffer.clear();

    m_remoteHost = ip;
    m_remotePort = port;

    qDebug() << "[NetworkClient] Connecting to" << ip << port << "...";

    m_socket->connectToHost(ip, port);
    m_connectTimer->start(kConnectTimeoutMs);
}

void NetworkClient::disconnectFromServer()
{
    m_socket->abort();       // 强行物理中止，瞬间拔掉 TCP 管道
    m_readBuffer.clear();
    setConnected(false);
}

// ============================================================================
// sendRequest —【上行】封包发送：4B 大端长度头 + JSON Body
//
// 后端 BusinessServer::tryExtractPacket 严格依赖前 4 字节大端 uint32_t
// 作为 Body 长度。此处必须与后端完全对齐。
// ============================================================================

void NetworkClient::sendRequest(const QString&    action,
                                const QJsonObject& body)
{
    if (!m_connected) {
        qWarning() << "[NetworkClient] sendRequest failed: not connected";
        emit connectionError(QStringLiteral("未连接到服务器"));
        return;
    }

    QJsonObject fullJson = body;
    fullJson[QStringLiteral("action")] = action;

    QJsonDocument doc(fullJson);
    QByteArray jsonBytes = doc.toJson(QJsonDocument::Compact);

    if (jsonBytes.size() > static_cast<int>(kMaxBodyLen)) {
        qWarning() << "[NetworkClient] Request too large:" << jsonBytes.size() << "bytes";
        emit connectionError(QStringLiteral("请求报文过大"));
        return;
    }

    // 构建 [4B BigEndian len][JSON bytes] 总包
    QByteArray packet;
    {
        QDataStream stream(&packet, QIODevice::WriteOnly);
        stream.setByteOrder(QDataStream::BigEndian);
        stream << static_cast<quint32>(jsonBytes.size());
    }
    packet.append(jsonBytes);

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
// readLocalFileGbk — GBK/UTF-8 自适应文件读取
// ============================================================================

QString NetworkClient::readLocalFileGbk(const QString& path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "[NetworkClient] Cannot open file:" << path;
        return {};
    }

    QByteArray raw = file.readAll();
    file.close();

    if (raw.isEmpty())
        return {};

    return QString::fromUtf8(raw);
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

    m_socket->abort();

    emit connectionError(
        QStringLiteral("连接超时：无法连接到 %1:%2")
            .arg(m_remoteHost)
            .arg(m_remotePort));
}

// ============================================================================
// slotReadyRead —【下行】明文粘包自适应分割状态机
//
// 后端 sendResponse 吐出裸 JSON 字节流，无长度头。
// 当多个响应在 TCP 接收缓冲区发生连环粘包时，通过大括号计数器
// 精准定位每个独立 JSON 对象的物理边界，逐个切出发射。
//
// 半包处理：若当前缓冲区内的字节无法构成完整 JSON（大括号未闭环），
// 则保留残余数据挂起等待下次 readyRead 拼接。
// ============================================================================

void NetworkClient::slotReadyRead()
{
    m_readBuffer.append(m_socket->readAll());

    while (m_readBuffer.size() > 0) {
        int braceCount = 0;
        int packetLength = 0;
        bool foundPacket = false;

        for (int i = 0; i < m_readBuffer.size(); ++i) {
            char ch = m_readBuffer.at(i);
            if (ch == '{') {
                braceCount++;
            } else if (ch == '}') {
                braceCount--;
                if (braceCount == 0) {
                    packetLength = i + 1;
                    foundPacket = true;
                    break;
                }
            }
        }

        if (!foundPacket) {
            break;  // 半包：大括号未闭环，保留 m_readBuffer 挂起等待
        }

        QByteArray singleJsonData = m_readBuffer.left(packetLength);
        m_readBuffer.remove(0, packetLength);

        if (!singleJsonData.isEmpty()) {
            processJsonPacket(singleJsonData);
        }
    }
}

// ============================================================================
// slotErrorOccurred — 套接字异常处理
// ============================================================================

void NetworkClient::slotErrorOccurred(QAbstractSocket::SocketError error)
{
    Q_UNUSED(error)

    QString errorMsg = m_socket->errorString();

    qWarning() << "[NetworkClient] Socket error:" << errorMsg;

    m_connectTimer->stop();

    if (m_socket->state() != QAbstractSocket::ConnectedState) {
        setConnected(false);
    }

    emit connectionError(QStringLiteral("网络错误: %1").arg(errorMsg));
}

// ============================================================================
// processJsonPacket — JSON 解析与信号发射
// ============================================================================

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

    QString action = obj.value(QStringLiteral("action")).toString();
    if (action.isEmpty()) {
        action = obj.value(QStringLiteral("status")).toString();
    }

    qDebug() << "[NetworkClient] Response received:"
             << "action/status =" << action
             << "size =" << jsonData.size() << "bytes";

    emit responseReceived(action, obj);
}
