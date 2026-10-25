// Optional Qt 6 input/render smoke test; see docs/DEVELOPMENT.md.
// Uses the real PaperSurface, but no shell, state file, or physical input device.
#include <QGuiApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMouseEvent>
#include <QPointingDevice>
#include <QQuickItem>
#include <QQuickView>
#include <QTabletEvent>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>
#include <cstdio>
#include <cstdlib>

static void require(bool condition, const char *message) {
    if (!condition) {
        std::fprintf(stderr, "%s\n", message);
        std::exit(1);
    }
}

static QJsonObject snapshot(QQuickItem *root) {
    QVariant result;
    require(QMetaObject::invokeMethod(root, "snapshot", Q_RETURN_ARG(QVariant, result)), "snapshot failed");
    return QJsonDocument::fromJson(result.toString().toUtf8()).object();
}

static void reset(QQuickItem *root) {
    require(QMetaObject::invokeMethod(root, "reset"), "reset failed");
    QTest::qWait(50);
}

static int inkWidth(const QImage &image, int x, int y) {
    int count = 0;
    for (int row = y - 16; row <= y + 16; ++row) {
        const auto color = image.pixelColor(x, row);
        count += color.red() < 128 && color.green() < 128 && color.blue() < 128;
    }
    return count;
}

// Integrated darkness accounts for antialiased subpixel width changes in dots.
static qint64 inkWeight(const QImage &image, int x, int y) {
    const int background = image.pixelColor(x + 16, y + 16).red();
    qint64 weight = 0;
    for (int row = y - 16; row <= y + 16; ++row)
        for (int column = x - 16; column <= x + 16; ++column)
            weight += qMax(0, background - image.pixelColor(column, row).red());
    return weight;
}

int main(int argc, char **argv) {
    qputenv("QT_SCALE_FACTOR", "1"); // deterministic offscreen pixel checks
    QCoreApplication::setAttribute(Qt::AA_SynthesizeMouseForUnhandledTabletEvents);
    QGuiApplication app(argc, argv);
    require(argc == 2, "usage: pressure-input /absolute/path/to/tests/PressureHarness.qml");
    QQuickView view;
    view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    require(view.status() == QQuickView::Ready, "QML fixture did not load");
    view.show();
    require(QTest::qWaitForWindowExposed(&view), "fixture was not exposed");
    QTest::qWait(100);
    auto *root = view.rootObject();
    auto *paper = root->findChild<QQuickItem *>("paper");
    require(paper, "paper was not created");
    QPointingDevice pen("Pressure test pen", 1001, QInputDevice::DeviceType::Stylus,
        QPointingDevice::PointerType::Pen,
        QInputDevice::Capability::Position | QInputDevice::Capability::Pressure, 1, 3);
    QPointingDevice fixedPen("Fixed-width test pen", 1002, QInputDevice::DeviceType::Stylus,
        QPointingDevice::PointerType::Pen, QInputDevice::Capability::Position, 1, 3);
    const auto tablet = [&](QEvent::Type type, QPointF local, qreal pressure,
                            const QPointingDevice *device = nullptr, bool down = true) {
        const QPointF scene = paper->mapToScene(local);
        QTabletEvent event(type, device ? device : &pen, scene, view.mapToGlobal(scene.toPoint()), pressure,
            0, 0, 0, 0, 0, Qt::NoModifier,
            type == QEvent::TabletMove ? Qt::NoButton : Qt::LeftButton,
            type == QEvent::TabletRelease || !down ? Qt::NoButton : Qt::LeftButton);
        QCoreApplication::sendEvent(&view, &event);
        QCoreApplication::processEvents();
    };
    const auto syntheticMouse = [&](QEvent::Type type, QPointF local) {
        const QPointF scene = paper->mapToScene(local);
        QMouseEvent event(type, scene, scene, view.mapToGlobal(scene.toPoint()),
            type == QEvent::MouseMove ? Qt::NoButton : Qt::LeftButton,
            type == QEvent::MouseButtonRelease ? Qt::NoButton : Qt::LeftButton,
            Qt::NoModifier, Qt::MouseEventSynthesizedByQt, &pen);
        QCoreApplication::sendEvent(&view, &event);
        QCoreApplication::processEvents();
    };
    const auto frame = [&] {
        QTest::qWait(100);
        const auto image = view.grabWindow();
        require(!image.isNull(), "offscreen capture failed");
        return image;
    };

    tablet(QEvent::TabletPress, {80, 150}, 0.1);
    require(snapshot(root)["pressure"].toBool(), "native pen did not enable pressure");
    require(snapshot(root)["active"].toArray().first().toArray().size() == 3,
        "pen press did not capture pressure");
    require(!snapshot(root)["steady"].toBool(), "mouse smoothing was applied to a pen");
    syntheticMouse(QEvent::MouseButtonPress, {80, 150});
    tablet(QEvent::TabletMove, {260, 150}, 0.5);
    syntheticMouse(QEvent::MouseMove, {260, 150});
    tablet(QEvent::TabletMove, {440, 150}, 1);
    const auto wet = frame();
    require(inkWidth(wet, 100, 150) > 0 && inkWidth(wet, 420, 150) > inkWidth(wet, 100, 150),
        "pressure did not visibly change live stroke width");
    tablet(QEvent::TabletRelease, {600, 300}, 0);
    syntheticMouse(QEvent::MouseButtonRelease, {600, 300});
    const auto dry = frame();
    const auto state = snapshot(root);
    require(state["commits"].toInt() == 1, "pen/synthetic mouse stream did not commit exactly once");
    const auto points = state["objects"].toArray().first().toObject()["points"].toArray();
    require(points.size() == 3, "synthesized mouse events duplicated pen samples");
    require(points.first().toArray()[2].toDouble() == 0.1, "first pressure was lost");
    require(points.last().toArray()[0].toDouble() == 440 && points.last().toArray()[2].toDouble() == 1,
        "release added a zero-pressure or displaced endpoint");
    require(wet.copy(60, 130, 400, 40) == dry.copy(60, 130, 400, 40), "ink changed on release");
    for (int x = 80; x <= 440; ++x) {
        if (inkWidth(dry, x, 150) == 0) {
            std::fprintf(stderr, "Ink gap at x=%d\n", x);
            require(false, "tapered segments left an ink gap");
        }
    }
    require(inkWidth(dry, 600, 300) == 0, "release painted an extra segment");

    // The actual PNG export path must use the same ink, including selection removal.
    paper->setProperty("selectedObjectId", "stroke-1");
    QTemporaryDir exports;
    require(exports.isValid(), "temporary export folder failed");
    const QString pngPath = exports.filePath("pressure.png");
    require(QMetaObject::invokeMethod(root, "exportPng", Q_ARG(QVariant, pngPath)), "export invocation failed");
    require(QTest::qWaitFor([&] { return root->property("exportDone").toBool(); }, 5000), "export timed out");
    require(root->property("exportOk").toBool(), "PNG export failed");
    const QImage png(pngPath);
    require(!png.isNull() && inkWidth(png, 420, 150) == inkWidth(dry, 420, 150), "export changed ink width");
    require(inkWidth(png, 100, 150) == inkWidth(dry, 100, 150), "export changed light pressure");

    reset(root);
    tablet(QEvent::TabletPress, {100, 200}, 0.1);
    tablet(QEvent::TabletMove, {100, 200}, 0.9);
    const auto firmDot = frame();
    tablet(QEvent::TabletMove, {100, 200}, 0.2);
    tablet(QEvent::TabletRelease, {100, 200}, 0);
    const auto finishedDot = frame();
    require(snapshot(root)["commits"].toInt() == 1, "stationary pen did not commit once");
    require(inkWidth(firmDot, 100, 200) >= 9, "stationary pressure increase was lost");
    require(inkWidth(finishedDot, 100, 200) == inkWidth(firmDot, 100, 200), "easing off shrank a held dot");

    reset(root);
    tablet(QEvent::TabletMove, {100, 200}, 0, nullptr, false);
    require(snapshot(root)["active"].toArray().isEmpty() && snapshot(root)["commits"].toInt() == 0,
        "pen hover drew a stroke");
    tablet(QEvent::TabletPress, {100, 200}, 0);
    tablet(QEvent::TabletRelease, {100, 200}, 0);
    const auto lightDot = frame();
    require(inkWidth(lightDot, 100, 200) > 0 && inkWidth(lightDot, 100, 200) < 8,
        "zero pressure was treated as missing pressure or an invisible dot");

    reset(root);
    tablet(QEvent::TabletPress, {100, 200}, 1);
    tablet(QEvent::TabletRelease, {100, 200}, 0);
    const auto broadDot = frame();

    reset(root);
    tablet(QEvent::TabletPress, {100, 200}, 0, &fixedPen);
    tablet(QEvent::TabletRelease, {100, 200}, 0, &fixedPen);
    const auto fixed = snapshot(root)["objects"].toArray().first().toObject()["points"].toArray();
    require(fixed.first().toArray().size() == 2, "a pen without pressure acquired pressure metadata");
    const auto fixedDot = frame();
    require(inkWidth(fixedDot, 100, 200) >= 11, "a pen without pressure did not use full selected width");
    const auto fixedWeight = inkWeight(fixedDot, 100, 200);
    require(inkWeight(broadDot, 100, 200) > fixedWeight * 1.15
        && inkWeight(broadDot, 100, 200) < fixedWeight * 1.30,
        "firm-pressure ink did not include the modest width boost");
    require(inkWeight(lightDot, 100, 200) > fixedWeight * 0.06
        && inkWeight(lightDot, 100, 200) < fixedWeight * 0.115,
        "light-pressure ink did not use the finer minimum width");

    reset(root);
    paper->setScale(0.8);
    paper->setRotation(5);
    tablet(QEvent::TabletPress, {120, 220}, 0.25);
    tablet(QEvent::TabletMove, {360, 220}, 0.75);
    tablet(QEvent::TabletRelease, {360, 220}, 0);
    const auto transformed = snapshot(root)["objects"].toArray().first().toObject()["points"].toArray();
    require(transformed.first().toArray()[0].toDouble() == 120 && transformed.first().toArray()[1].toDouble() == 220
        && transformed.last().toArray()[0].toDouble() == 360, "pen coordinates ignored paper scale/rotation");
    paper->setScale(1);
    paper->setRotation(0);

    reset(root);
    tablet(QEvent::TabletPress, {80, 250}, 0.5);
    require(QMetaObject::invokeMethod(paper, "cancelGesture"), "cancel failed");
    tablet(QEvent::TabletRelease, {440, 250}, 0);
    require(snapshot(root)["commits"].toInt() == 0 && snapshot(root)["objects"].toArray().isEmpty(),
        "cancelled pen gesture committed ink");

    reset(root);
    tablet(QEvent::TabletPress, {80, 250}, 0.5);
    paper->setProperty("currentTool", "select");
    tablet(QEvent::TabletMove, {440, 250}, 1);
    tablet(QEvent::TabletRelease, {440, 250}, 0);
    require(snapshot(root)["commits"].toInt() == 0, "changing tools committed or restarted a cancelled pen gesture");

    reset(root);
    tablet(QEvent::TabletPress, {80, 250}, 0.5);
    paper->setEnabled(false);
    tablet(QEvent::TabletRelease, {440, 250}, 0);
    paper->setEnabled(true);
    require(snapshot(root)["commits"].toInt() == 0, "disabling the paper committed a cancelled pen gesture");

    reset(root);
    tablet(QEvent::TabletPress, {80, 250}, 0.5);
    paper->setVisible(false);
    tablet(QEvent::TabletRelease, {440, 250}, 0);
    paper->setVisible(true);
    require(snapshot(root)["commits"].toInt() == 0, "hiding the paper committed a cancelled pen gesture");

    reset(root);
    require(QMetaObject::invokeMethod(paper, "editTitle"), "title fixture failed");
    tablet(QEvent::TabletPress, {80, 250}, 0.5);
    tablet(QEvent::TabletMove, {440, 250}, 1);
    tablet(QEvent::TabletRelease, {440, 250}, 0);
    require(snapshot(root)["commits"].toInt() == 0, "leaving the title editor painted an accidental stroke");
    tablet(QEvent::TabletPress, {80, 250}, 0.5);
    tablet(QEvent::TabletRelease, {80, 250}, 0);
    require(snapshot(root)["commits"].toInt() == 1, "pen did not resume after leaving the title editor");

    reset(root);
    tablet(QEvent::TabletPress, {80, 150}, 0.5);
    require(QMetaObject::invokeMethod(root, "fillStroke"), "point-limit fixture failed");
    require(snapshot(root)["active"].toArray().size() == 8192 && snapshot(root)["full"].toBool(),
        "live pressure capture exceeded the stroke point budget");
    require(QMetaObject::invokeMethod(paper, "cancelGesture"), "limit fixture cancel failed");
    tablet(QEvent::TabletRelease, {80, 150}, 0);

    reset(root);
    QTest::mousePress(&view, Qt::LeftButton, Qt::NoModifier, {80, 250});
    require(!snapshot(root)["pressure"].toBool(), "mouse inherited pen pressure");
    QTest::mouseMove(&view, {440, 250});
    QTest::mouseRelease(&view, Qt::LeftButton, Qt::NoModifier, {440, 250});
    require(snapshot(root)["commits"].toInt() == 1, "mouse did not commit exactly once");
    const auto mousePoints = snapshot(root)["objects"].toArray().first().toObject()["points"].toArray();
    for (const auto &point : mousePoints)
        require(point.toArray().size() == 2, "mouse stroke acquired pressure metadata");
    require(inkWidth(frame(), 260, 250) >= 11, "mouse width changed");
    std::puts("Pressure input/render smoke test passed (native pen, synthetic duplicates, PNG, dots, fallback, transforms, cancellation, limits, mouse)");
}
