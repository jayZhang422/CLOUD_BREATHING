from PySide6.QtCore import QObject, Property, Signal, Slot

from .database import initialize_database, open_database


class PatientQueue(QObject):
    changed = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._rows = []
        initialize_database()
        self.refresh()

    rows = Property("QVariantList", lambda self: self._rows, notify=changed)

    @Slot()
    def refresh(self) -> None:
        with open_database() as connection:
            records = connection.execute(
                """SELECT id, patient_name, patient_id, institution_name,
                          study_description, modality, series_description,
                          slice_count, rows, columns, created_at
                   FROM ct_studies ORDER BY id DESC"""
            ).fetchall()
        self._rows = [
            {
                "studyId": record["id"],
                "patientName": record["patient_name"],
                "patientId": record["patient_id"],
                "institution": record["institution_name"],
                "studyDescription": record["study_description"],
                "modality": record["modality"],
                "seriesDescription": record["series_description"],
                "sliceCount": record["slice_count"],
                "dimensions": f"{record['columns']} × {record['rows']}",
                "createdAt": record["created_at"],
                "status": "已入库",
            }
            for record in records
        ]
        # Stable alias by import order: the oldest study is 病人1.
        for rank, row in enumerate(sorted(self._rows, key=lambda r: r["studyId"]), 1):
            row["alias"] = f"病人{rank}"
        self.changed.emit()
