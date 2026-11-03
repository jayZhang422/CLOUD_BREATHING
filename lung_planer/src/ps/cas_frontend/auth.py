from PySide6.QtCore import QObject, Property, Signal, Slot


class SessionController(QObject):
    authenticatedChanged = Signal()
    loginErrorChanged = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._authenticated = False
        self._login_error = ""
        self._register_error = ""
        self._users = {"cloud": "cloud2026"}

    @Property(bool, notify=authenticatedChanged)
    def authenticated(self) -> bool:
        return self._authenticated

    @Property(str, notify=loginErrorChanged)
    def loginError(self) -> str:
        return self._login_error

    @Property(str, notify=loginErrorChanged)
    def registerError(self) -> str:
        return self._register_error

    @Slot(str, str)
    def login(self, username: str, password: str) -> None:
        # Replace this demo check with the KV260 backend authentication call.
        if self._users.get(username.strip()) == password:
            self._login_error = ""
            self._authenticated = True
            self.loginErrorChanged.emit()
            self.authenticatedChanged.emit()
            return
        self._login_error = "账号或密码不正确"
        self.loginErrorChanged.emit()

    @Slot(str, str, str)
    def registerAccount(self, username: str, password: str, confirmation: str) -> None:
        username = username.strip()
        if len(username) < 3:
            self._register_error = "账号至少需要 3 个字符"
        elif username in self._users:
            self._register_error = "该账号已存在"
        elif len(password) < 6:
            self._register_error = "密码至少需要 6 个字符"
        elif password != confirmation:
            self._register_error = "两次输入的密码不一致"
        else:
            self._users[username] = password
            self._register_error = ""
            self._authenticated = True
            self.loginErrorChanged.emit()
            self.authenticatedChanged.emit()
        self.loginErrorChanged.emit()

    @Slot()
    def logout(self) -> None:
        self._authenticated = False
        self._login_error = ""
        self.loginErrorChanged.emit()
        self.authenticatedChanged.emit()
