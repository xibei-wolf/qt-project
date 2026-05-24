// ============================================================================
// NetworkClient.h — 青云志愿服务队管理系统 · 跨平台网络客户端单例
//
// 非对称网关协议（与 Linux Muduo 服务端 100% 对齐）：
//
//   客户端 → 服务端（sendRequest）：
//     ┌──────────────────┬───────────────────────────────┐
//     │ uint32_t bodyLen  │  JSON Body (UTF-8)            │
//     │ (4B, Big-Endian)  │  (bodyLen 字节)               │
//     └──────────────────┴───────────────────────────────┘
//     后端 tryExtractPacket 严格解析 4 字节大端长度头。
//
//   服务端 → 客户端（slotReadyRead）：
//     纯明文裸流 JSON，无长度头。
//     后端 sendResponse 直接吐出裸 JSON 字节流。
// ============================================================================

#pragma once

#include <QObject>
#include <QJsonObject>
#include <QJsonDocument>
#include <QTcpSocket>
#include <QDataStream>
#include <QTimer>
#include <QAbstractSocket>

class NetworkClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged FINAL)

public:
    static NetworkClient* instance();

    NetworkClient(const NetworkClient&) = delete;
    NetworkClient& operator=(const NetworkClient&) = delete;

    Q_INVOKABLE void connectToServer(const QString& ip, quint16 port);
    Q_INVOKABLE void disconnectFromServer();

    /// 发送请求（自动封装 4B 大端长度头 + JSON Body）
    Q_INVOKABLE void sendRequest(const QString&    action,
                                 const QJsonObject& body = QJsonObject());

    /// 读取本地文件（GBK/UTF-8 自适应解码）
    Q_INVOKABLE QString readLocalFileGbk(const QString& path);

    bool isConnected() const;
    QString remoteAddress() const;

signals:
    void connectedChanged(bool connected);
    void responseReceived(const QString& action, const QJsonObject& data);
    void connectionError(const QString& errorString);

private slots:
    void slotConnected();
    void slotDisconnected();
    void slotReadyRead();
    void slotErrorOccurred(QAbstractSocket::SocketError error);
    void slotConnectTimeout();

private:
    explicit NetworkClient(QObject* parent = nullptr);
    ~NetworkClient() override;

    void setConnected(bool connected);
    void processJsonPacket(const QByteArray& jsonData);

    QTcpSocket* m_socket       = nullptr;
    QTimer*     m_connectTimer = nullptr;

    QByteArray  m_readBuffer;                 // 下行裸流粘包分割缓冲区

    bool        m_connected     = false;
    QString     m_remoteHost;
    quint16     m_remotePort    = 0;

    static constexpr int    kConnectTimeoutMs = 5000;
    static constexpr quint32 kMaxBodyLen      = 4 * 1024 * 1024;  // 4 MB
};
