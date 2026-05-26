cmake_minimum_required(VERSION 3.16)

project(Qinyun VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Network QuickControls2)
qt_standard_project_setup(REQUIRES 6.8)

# 显式把你的 C++ 管道文件包含进来
qt_add_executable(appQinyun
    main.cpp
    network/NetworkClient.h
    network/NetworkClient.cpp
)

qt_add_qml_module(appQinyun
    URI Qinyun
    QML_FILES
        Main.qml
        views/ActivityDispatchView.qml
        views/ActivityManagementView.qml
        views/ActivitySchedulerDialog.qml
        views/AddActivityDialog.qml
        views/MemberManagementView.qml
        views/ScheduleUploadView.qml
        js/EventRecurrenceLogic.js
    SOURCES
        main.cpp
        network/NetworkClient.h
        network/NetworkClient.cpp
        SOURCES
        RESOURCES
)

set_target_properties(appQinyun PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appQinyun
    PRIVATE Qt6::Quick Qt6::Network
    Qt6::QuickControls2
)

# 1. 强制把当前目录和子目录（network）加入编译器的头文件搜索路径
target_include_directories(appQinyun PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})


include(GNUInstallDirs)
install(TARGETS appQinyun
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

