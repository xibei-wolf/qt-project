#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include "network/NetworkClient.h"

int main(int argc, char *argv[])
{
    QQuickStyle::setStyle("Basic");
    QGuiApplication app(argc, argv);
    QQmlApplicationEngine engine;
    // 注册 NetworkClient 单例到 QML 上下文
    NetworkClient* networkClient = NetworkClient::instance();
    engine.rootContext()->setContextProperty(QStringLiteral("NetworkClient"),
                                             networkClient);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("Qinyun", "Main");

    return app.exec();
}
