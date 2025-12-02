# Testbench I2C para Sensor LM75

## Descripción

Este testbench simula la comunicación I2C entre un maestro FPGA y un sensor de temperatura LM75. Incluye:

1. **Modelo comportamental del sensor LM75** - Simula el comportamiento del sensor real
2. **Maestro I2C modificado** - Versión adaptada del i2c_master para comunicarse con LM75
3. **Estímulos y verificación** - Pruebas automatizadas del protocolo I2C

## Características del LM75

- **Dirección I2C**: 0x48 (base) → 0x91 con bit de lectura
- **Formato de temperatura**: 11 bits, complemento a dos
- **Registro de temperatura**: 16 bits (MSB + LSB)
- **Resolución**: 0.5°C por LSB
- **Formato**: D10-D3 en MSB, D2-D0 en bits [7:5] del LSB

## Estructura del Testbench

```
i2c_lm75_tb.v
├── i2c_lm75_tb (módulo principal)
│   ├── Generación de relojes (100MHz y 200KHz)
│   ├── Modelo comportamental del LM75 (esclavo)
│   │   ├── Detección de condiciones START/STOP
│   │   ├── Máquina de estados del protocolo I2C
│   │   ├── Verificación de dirección
│   │   └── Envío de datos de temperatura
│   ├── Instancia del maestro I2C
│   └── Monitores de señales y transacciones
│
└── i2c_master_lm75 (maestro I2C)
    ├── Generador de reloj SCL (10KHz)
    ├── Máquina de estados I2C
    └── Manejo de señal SDA bidireccional
```

## Protocolo I2C Implementado

### Secuencia de Lectura de Temperatura

```
1. START condition
2. Envío de dirección del sensor (7 bits) + bit de lectura (1)
   - Dirección: 0x48 (1001000)
   - Bit R/W: 1 (lectura)
   - Total: 0x91 (10010001)
3. LM75 envía ACK
4. LM75 envía MSB (8 bits)
5. Maestro envía ACK
6. LM75 envía LSB (8 bits)
7. Maestro envía NACK
8. STOP condition
9. Repetir desde paso 1
```

## Estados del LM75 (Esclavo)

| Estado | Descripción |
|--------|-------------|
| `LM75_IDLE` | Estado de espera |
| `LM75_REC_ADDR` | Recibiendo dirección de 8 bits |
| `LM75_SEND_ACK` | Enviando ACK (reconocimiento) |
| `LM75_SEND_MSB` | Enviando byte más significativo |
| `LM75_REC_ACK_MSB` | Recibiendo ACK del maestro |
| `LM75_SEND_LSB` | Enviando byte menos significativo |
| `LM75_REC_NACK` | Recibiendo NACK (fin de lectura) |

## Requisitos

### Software necesario:

- **Icarus Verilog** (iverilog) - Compilador/simulador Verilog
- **GTKWave** (opcional) - Visor de formas de onda

### Instalación en Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install iverilog gtkwave
```

### Instalación en macOS:

```bash
brew install icarus-verilog gtkwave
```

### Instalación en Windows:

Descargar desde:
- Icarus Verilog: http://bleyer.org/icarus/
- GTKWave: http://gtkwave.sourceforge.net/

## Uso

### Método 1: Usando el script (Linux/macOS)

```bash
# Dar permisos de ejecución
chmod +x run_sim.sh clean_sim.sh

# Ejecutar simulación
./run_sim.sh

# Limpiar archivos generados
./clean_sim.sh
```

### Método 2: Comandos manuales

```bash
# Compilar
iverilog -o i2c_lm75_sim i2c_lm75_tb.v

# Ejecutar simulación
vvp i2c_lm75_sim

# Ver formas de onda
gtkwave i2c_lm75_tb.vcd
```

## Salida de la Simulación

La simulación genera mensajes informativos en la consola:

```
=================================================================
Starting I2C LM75 Temperature Sensor Simulation
=================================================================
LM75 Temperature Register = 0x1900 (Should be 25°C)

[time] LM75: START condition detected
[time] I2C: Address bit 0 = 1
[time] I2C: Address bit 1 = 0
...
[time] LM75: Address match! Received: 0x91
[time] LM75: Sending ACK
[time] LM75: Preparing to send MSB: 0x19
[time] LM75: ACK received after MSB
[time] LM75: Preparing to send LSB: 0x00
[time] LM75: NACK received after LSB (expected)
[time] Master received temperature data: 0x19 (25°C)
[time] LM75: STOP condition detected
```

## Visualización con GTKWave

1. Abrir el archivo VCD:
   ```bash
   gtkwave i2c_lm75_tb.vcd
   ```

2. Señales importantes a visualizar:
   - `SCL` - Reloj I2C
   - `SDA` - Línea de datos I2C
   - `temp_data` - Dato de temperatura recibido
   - `lm75_state` - Estado del sensor LM75
   - `state_reg` - Estado del maestro I2C

3. Buscar:
   - Condiciones START (SDA cae mientras SCL está alto)
   - Condiciones STOP (SDA sube mientras SCL está alto)
   - Transferencia de bits de dirección
   - Pulsos ACK/NACK (SDA bajo/alto durante pulso SCL)
   - Transferencia de datos MSB y LSB

## Modificación de Parámetros de Prueba

### Cambiar temperatura simulada:

En `i2c_lm75_tb.v`, línea ~42:

```verilog
reg [15:0] lm75_temp_register = 16'h1900;  // 25°C
```

Ejemplos de valores de temperatura:

| Temperatura | Valor Hexadecimal | Binario |
|-------------|-------------------|---------|
| 0°C | 0x0000 | 0000_0000_0000_0000 |
| 25°C | 0x1900 | 0001_1001_0000_0000 |
| 50°C | 0x3200 | 0011_0010_0000_0000 |
| 75°C | 0x4B00 | 0100_1011_0000_0000 |
| 100°C | 0x6400 | 0110_0100_0000_0000 |
| -25°C | 0xE700 | 1110_0111_0000_0000 |

### Cambiar dirección del LM75:

En `i2c_master_lm75` módulo, línea ~20:

```verilog
parameter [7:0] sensor_address_plus_read = 8'b1001_0001;  // 0x91
```

Direcciones válidas del LM75 (con bit de lectura):
- 0x90/0x91 - Dirección base 0x48
- 0x92/0x93 - Dirección base 0x49
- 0x94/0x95 - Dirección base 0x4A
- 0x96/0x97 - Dirección base 0x4B

## Diferencias entre LM75 y ADT7420

| Característica | LM75 | ADT7420 |
|----------------|------|---------|
| Dirección I2C | 0x48-0x4F | 0x48-0x4B |
| Resolución | 9 bits (0.5°C) | 13 bits (0.0625°C) |
| Bits de temperatura | 11 bits | 13 bits |
| Formato de datos | D10-D3 en MSB | D12-D3 en MSB |
| Exactitud | ±2°C | ±0.25°C |

## Solución de Problemas

### Error: "command not found: iverilog"
**Solución**: Instalar Icarus Verilog (ver sección de Requisitos)

### Error: "Permission denied"
**Solución**:
```bash
chmod +x run_sim.sh
```

### No se generan mensajes de salida
**Solución**: Verificar que los comandos `$display` estén habilitados y que la simulación corra suficiente tiempo

### Señales aparecen como 'x' o 'z' en GTKWave
**Solución**:
- Verificar que el modelo del LM75 esté respondiendo correctamente
- Revisar la lógica del pull-up en la señal SDA
- Verificar timings de setup/hold del protocolo I2C

## Extensiones Posibles

1. **Agregar pruebas de escritura**: Implementar escritura al registro de configuración
2. **Probar múltiples direcciones**: Simular varios sensores en el mismo bus
3. **Agregar errores**: Probar condiciones de error (NACK, timeout, etc.)
4. **Probar stretching de reloj**: Implementar clock stretching del esclavo
5. **Agregar registro de histéresis**: Simular registro Tos y Thyst del LM75

## Referencias

- **LM75 Datasheet**: https://www.ti.com/lit/ds/symlink/lm75b.pdf
- **I2C Specification**: https://www.nxp.com/docs/en/user-guide/UM10204.pdf
- **Icarus Verilog**: http://iverilog.icarus.com/
- **GTKWave**: http://gtkwave.sourceforge.net/

## Autor

Testbench creado para el proyecto "Improved I2C Nexys A7 Temperature Sensor"

## Licencia

Este código es para propósitos educativos y de desarrollo.
