import sqlite3
from pathlib import Path

DATABASE_PATH = Path(__file__).resolve().parents[1] / "data" / "cloud_breathing.db"

def open_database() -> sqlite3.Connection:
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA journal_mode=WAL")
    connection.execute("PRAGMA foreign_keys=ON")
    connection.execute("PRAGMA busy_timeout=5000")
    return connection


def initialize_database() -> None:
    with open_database() as connection:
        connection.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS device_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                level TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS ct_studies (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                patient_name TEXT NOT NULL,
                patient_id TEXT NOT NULL,
                institution_name TEXT NOT NULL,
                study_description TEXT NOT NULL,
                modality TEXT NOT NULL,
                series_description TEXT NOT NULL,
                slice_count INTEGER NOT NULL,
                rows INTEGER NOT NULL,
                columns INTEGER NOT NULL,
                source_directory TEXT NOT NULL,
                output_directory TEXT NOT NULL,
                metadata_json TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS ct_slices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                study_id INTEGER NOT NULL REFERENCES ct_studies(id) ON DELETE CASCADE,
                plane TEXT NOT NULL CHECK (plane IN ('axial', 'coronal', 'sagittal')),
                slice_index INTEGER NOT NULL,
                image_path TEXT NOT NULL,
                UNIQUE(study_id, plane, slice_index)
            );
        """)


def save_ct_result(result) -> int:
    import json

    metadata = result.metadata
    initialize_database()
    with open_database() as connection:
        cursor = connection.execute(
            """INSERT INTO ct_studies (
                patient_name, patient_id, institution_name, study_description,
                modality, series_description, slice_count, rows, columns,
                source_directory, output_directory, metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                metadata["patient_name"], metadata["patient_id"], metadata["institution_name"],
                metadata["study_description"], metadata["modality"], metadata["series_description"],
                metadata["slice_count"], metadata["rows"], metadata["columns"],
                metadata["source_directory"], result.output_directory,
                json.dumps(metadata, ensure_ascii=False),
            ),
        )
        study_id = cursor.lastrowid
        output = Path(result.output_directory)
        rows = []
        for index in range(1, result.slice_count + 1):
            rows.append((study_id, "axial", index, str(output / "png" / f"slice_{index:04d}.png")))
        for index in range(1, metadata["columns"] + 1):
            rows.append((study_id, "coronal", index, str(output / "coronal" / f"slice_{index:04d}.png")))
        for index in range(1, metadata["rows"] + 1):
            rows.append((study_id, "sagittal", index, str(output / "sagittal" / f"slice_{index:04d}.png")))
        connection.executemany(
            "INSERT INTO ct_slices (study_id, plane, slice_index, image_path) VALUES (?, ?, ?, ?)",
            rows,
        )
        return int(study_id)
