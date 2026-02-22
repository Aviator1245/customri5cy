#define UART_ADDR ((volatile unsigned int*)0x100)

void uart_putchar(char c)
{
    *UART_ADDR = (unsigned int)c;
}

void print_str(const char *s)
{
    while (*s)
        uart_putchar(*s++);
}

void print_dec(int value)
{
    char buf[12];   // enough for 32-bit int
    int i = 0;

    if (value == 0) {
        uart_putchar('0');
        return;
    }

    if (value < 0) {
        uart_putchar('-');
        value = -value;
    }

    while (value > 0) {
        buf[i++] = '0' + (value % 10);
        value /= 10;
    }

    while (i--)
        uart_putchar(buf[i]);
}

