import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Single source of truth for the SQLite database.
class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  static Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'iron_eye_v1.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ATHLETE (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        name            TEXT    NOT NULL,
        bodyweight      REAL,
        height_cm       REAL,
        age             INTEGER,
        avatar          TEXT,
        gender          TEXT    DEFAULT 'male',
        training_level  TEXT    DEFAULT 'beginner',
        goal            TEXT    DEFAULT 'strength',
        weekly_workout_target INTEGER DEFAULT 5,
        weekly_rep_target     INTEGER DEFAULT 300,
        created_at      TEXT    NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE DEVICE (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        mac_address      TEXT,
        firmware_version TEXT,
        last_seen        TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE SESSION (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        athlete_id INTEGER NOT NULL,
        date       TEXT    NOT NULL,
        exercise   TEXT    NOT NULL,
        notes      TEXT,
        FOREIGN KEY (athlete_id) REFERENCES ATHLETE(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE WORKOUT_SET (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        exercise   TEXT    NOT NULL,
        set_index  INTEGER NOT NULL,
        load_kg    REAL,
        target_rpe REAL,
        FOREIGN KEY (session_id) REFERENCES SESSION(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE REP (
        id                       INTEGER PRIMARY KEY AUTOINCREMENT,
        set_id                   INTEGER NOT NULL,
        rep_index                INTEGER NOT NULL,
        mean_concentric_velocity REAL,
        peak_velocity            REAL,
        displacement_m           REAL,
        duration_ms              INTEGER,
        form_score               INTEGER,
        data_quality             TEXT    DEFAULT 'good',
        algorithm_version        TEXT    DEFAULT '1.0',
        timestamp                TEXT    NOT NULL,
        FOREIGN KEY (set_id) REFERENCES WORKOUT_SET(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE E1RM_ESTIMATE (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        athlete_id        INTEGER NOT NULL,
        exercise          TEXT    NOT NULL,
        date              TEXT    NOT NULL,
        estimated_1rm     REAL    NOT NULL,
        r_squared         REAL,
        n_points          INTEGER,
        algorithm_version TEXT    DEFAULT '1.0',
        FOREIGN KEY (athlete_id) REFERENCES ATHLETE(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE DEVICE_LOG (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id       INTEGER,
        session_id      INTEGER,
        packet_loss_pct REAL,
        avg_latency_ms  REAL,
        FOREIGN KEY (device_id)  REFERENCES DEVICE(id),
        FOREIGN KEY (session_id) REFERENCES SESSION(id)
      )
    ''');
  }
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE ATHLETE ADD COLUMN avatar TEXT');
    }
  }

  Future<void> deleteEverything() async {
    final db = await this.db;
    await db.transaction((txn) async {
      await txn.execute('DELETE FROM REP');
      await txn.execute('DELETE FROM WORKOUT_SET');
      await txn.execute('DELETE FROM SESSION');
      await txn.execute('DELETE FROM DEVICE_LOG');
      await txn.execute('DELETE FROM DEVICE');
      await txn.execute('DELETE FROM E1RM_ESTIMATE');
      await txn.execute('DELETE FROM ATHLETE');
    });
  }
}