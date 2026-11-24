# hci_qca.c 前置声明修复（mainline tb331fc 树自带缺陷）

树里的 drivers/bluetooth/hci_qca.c 存在函数先用后声明：

\\\
1423:  qca_set_speed(hu, QCA_INIT_SPEED);            <- 调用
1483:  static int qca_set_speed(struct hci_uart *hu, enum qca_speed_type speed_type)   <- 定义
\\\

编译报错：

\\\
error: implicit declaration of function 'qca_set_speed' [-Werror=implicit-function-declaration]
error: static declaration of 'qca_set_speed' follows non-static declaration
\\\

修法：在第一次调用之前加前置声明。

\\\c
/* forward declaration: qca_send_power_pulse() calls this before its definition */
static int qca_set_speed(struct hci_uart *hu, enum qca_speed_type speed_type);
\\\

插入位置：qca_send_power_pulse() 定义之前的文件作用域（本树为第 1397 行附近）。
