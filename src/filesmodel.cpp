#include "filesmodel.h"

#include <QDebug>

FilesModel::FilesModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_xMin(0.0)
    , m_xMax(0.0)
    , m_yMin(0.0)
    , m_yMax(0.0)
{

    m_trackColors << QRgb(0x209fdf);
    m_trackColors << QRgb(0x99ca53);
    m_trackColors << QRgb(0xf6a625);
    m_trackColors << QRgb(0x6d5fd5);
    m_trackColors << QRgb(0xbf593e);

//    m_trackColors << QColor("dodgerblue");
//    m_trackColors << QColor("mediumseagreen");
//    m_trackColors << QColor("deeppink");
//    m_trackColors << QColor("orangered");
//    m_trackColors << QColor("salmon");

//    m_trackColors << QColor("deepskyblue");
//    m_trackColors << QColor("darkturquoise");
//    m_trackColors << QColor("mediumorchid");
//    m_trackColors << QColor("indianred");
//    m_trackColors << QColor("firebrick");
}

int FilesModel::rowCount(const QModelIndex &parent) const
{
    // For list models only the root node (an invalid parent) should return the list's size. For all
    // other (valid) parents, rowCount() should return 0 so that it does not become a tree model.
    if (parent.isValid())
        return 0;

    return m_files.size();
}

QHash<int, QByteArray> FilesModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[DataRoles::NameRole] = "name";
    roles[DataRoles::TracksRole] = "tracks";
    roles[DataRoles::PoisRole] = "pois";
    roles[DataRoles::BoundingBoxRole] = "boundingBox";
    return roles;
}

QVariant FilesModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid())
        return QVariant();

    File *file = qobject_cast<File*>(m_files.at(index.row()));
    if (!file) {
        qWarning()<<QStringLiteral("Object is not of type File");
        return QVariant();
    }

    switch (role) {
    case DataRoles::NameRole:
        return file->name();
    case DataRoles::TracksRole:
        return QVariant::fromValue(file->tracks());
    case DataRoles::PoisRole:
        return QVariant::fromValue(file->pois());
    case DataRoles::BoundingBoxRole:
        return QVariant::fromValue(file->boundingBox());
    default:
        return QVariant();
    }
}

int FilesModel::count()
{
    return m_files.size();
}

File* FilesModel::get(int index)
{
    if (index < 0 || index > m_files.size()-1)
        return nullptr;

    return m_files.at(index);
}

void FilesModel::append(File* file)
{
    if (!file)
        return;

    beginInsertRows(QModelIndex(), m_files.size(), m_files.size());

    QObjectList tracks = file->tracks();
    for (auto t : tracks) {
        Track* track = static_cast<Track*>(t);
        int key = createUniqueKey(m_trackMap.values());
        track->setObjectName(QStringLiteral("track_")+QString::number(key));
        track->setColor(m_trackColors.at(key%m_trackColors.length()));

        if (m_trackMap.isEmpty()) {
            m_xMax = track->distance2D();
            m_yMin = track->altitudeMin();
            m_yMax = track->altitudeMax();
        } else {
            m_xMax = qMax(m_xMax, track->distance2D());
            m_yMin = qMin(m_yMin, track->altitudeMin());
            m_yMax = qMax(m_yMax, track->altitudeMax());
        }
        connect(track, &Track::pathChanged, this, &FilesModel::updateExtrema);

        m_trackMap.insert(track,key);
        Q_EMIT(extremaChanged());
    }
    QObjectList pois = file->pois();
    for (auto p : pois) {
        Poi* poi = static_cast<Poi*>(p);
        int key = createUniqueKey(m_poiMap.values());
        poi->setObjectName(QStringLiteral("poi_")+QString::number(key));
        m_poiMap.insert(poi,key);
    }

    m_files.append(file);

    endInsertRows();

    Q_EMIT(countChanged());
    Q_EMIT(fileAppened(file));
}

void FilesModel::remove(int index)
{
    if (index > m_files.size())
        return;

    beginRemoveRows(QModelIndex(), index, index);

    File* file = m_files.at(index);
    QObjectList tracks = file->tracks();
    for (auto t : tracks) {
        Track* track = static_cast<Track*>(t);
        m_trackMap.remove(track);

        updateExtrema();
    }

    m_files.remove(index);

    endRemoveRows();

    Q_EMIT(countChanged());
    Q_EMIT(fileRemoved(file));
}

int FilesModel::createUniqueKey(QList<int> keys) const
{
    std::sort(keys.begin(), keys.end());
    int key = 0;
    auto it = keys.begin();
    while (it != keys.end()) {
        if (*it != key)
            break;
        ++key;
        ++it;
    }
    return key;
}

void FilesModel::updateExtrema()
{
    if (m_trackMap.isEmpty()) {
        m_xMax = 0.0;
        m_yMin = 0.0;
        m_yMax = 0.0;
    } else {
        for (auto t = m_trackMap.keyBegin(); t != m_trackMap.keyEnd(); ++t) {
            Track *track = *t;
            if (t == m_trackMap.keyBegin()) {
                m_xMax = track->distance2D();
                m_yMin = track->altitudeMin();
                m_yMax = track->altitudeMax();
            } else {
                m_xMax = qMax(m_xMax, track->distance2D());
                m_yMin = qMin(m_yMin, track->altitudeMin());
                m_yMax = qMax(m_yMax, track->altitudeMax());
            }
        }
    }
    Q_EMIT(extremaChanged());
}
