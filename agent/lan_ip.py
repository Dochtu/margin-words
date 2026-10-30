"""打印本机局域网 IPv4（供 start.bat 使用，避免批处理里写带括号的 Python 单行命令）。"""

import socket


def main() -> None:
    ip = "127.0.0.1"
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # UDP connect 不会真的发包，只用来选出默认出口网卡的地址
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        sock.close()
    except Exception:
        try:
            ip = socket.gethostbyname(socket.gethostname())
        except Exception:
            ip = "127.0.0.1"
    print(ip)


if __name__ == "__main__":
    main()
