TYPE ENUM_NetfluxSocketState :
(
    IDLE := 0,
    CREATE := 10,
    BIND := 20,
    NONBLOCK := 30,
    RUNNING := 40,
    ERROR := 99
) INT;
END_TYPE