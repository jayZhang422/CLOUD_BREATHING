"""Native Qt stores row data and performs filtering/sorting without Python callbacks."""
from PySide6.QtCore import QSortFilterProxyModel, Qt
from PySide6.QtGui import QStandardItem, QStandardItemModel

from .branch_presentation import affected_order


class BranchListModel(QStandardItemModel):
    RowRole = Qt.ItemDataRole.UserRole + 1
    AffectedRole = RowRole + 1
    SourceOrderRole = RowRole + 2
    AffectedOrderRole = RowRole + 3

    def __init__(self, parent=None):
        super().__init__(parent)
        self.rows = []
        self.setItemRoleNames({self.RowRole: b'branch', self.AffectedRole: b'affected',
            self.SourceOrderRole: b'sourceOrder', self.AffectedOrderRole: b'affectedOrder'})

    def replace(self, rows):
        if rows is self.rows:
            return
        ranks = {r['key']: i for i, r in enumerate(sorted(rows, key=affected_order))}
        same_keys = [r['key'] for r in rows] == [r['key'] for r in self.rows]
        changed = [i for i, (a, b) in enumerate(zip(self.rows, rows)) if a != b] if same_keys else list(range(len(rows)))
        if same_keys and not changed:
            self.rows = rows
            return
        if not same_keys:
            # A new extraction/model may reset; display toggles never do.
            self.beginResetModel()
        previous = self.blockSignals(True)
        try:
            if not same_keys:
                self.setRowCount(0)
            for i, row in enumerate(rows):
                item = self.item(i) if same_keys else QStandardItem()
                # Store QVariant maps once, rather than calling Python data()
                # thousands of times during native Qt view layout and sorting.
                if not same_keys or self.rows[i] != row:
                    item.setData(row, self.RowRole)
                item.setData('1' if row['status'] != 'outside' or row['downstream_affected'] else '0', self.AffectedRole)
                item.setData(i, self.SourceOrderRole)
                item.setData(ranks[row['key']], self.AffectedOrderRole)
                if not same_keys:
                    self.appendRow(item)
            self.rows = rows
        finally:
            self.blockSignals(previous)
        if not same_keys:
            # Notify views of the completed native model in one reset.
            self.endResetModel()
        elif rows:
            self.dataChanged.emit(self.index(0, 0), self.index(len(rows)-1, 0),
                [self.RowRole, self.AffectedRole, self.AffectedOrderRole])


class BranchFilterModel(QSortFilterProxyModel):
    def __init__(self, source, parent=None):
        super().__init__(parent)
        self.only_affected = True
        self.setSourceModel(source)
        self.setFilterRole(source.AffectedRole)
        self.setFilterFixedString('1')
        self.setSortRole(source.AffectedOrderRole)
        self.sort(0)

    def set_only_affected(self, value):
        if value == self.only_affected:
            return
        self.only_affected = value
        self.setFilterFixedString('1' if value else '')
        self.setSortRole(self.sourceModel().AffectedOrderRole if value else self.sourceModel().SourceOrderRole)
        self.sort(0)
