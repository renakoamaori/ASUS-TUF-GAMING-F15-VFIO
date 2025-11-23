# 🎮 ASUS TUF GAMING F15 - Guía de GPU Passthrough con VFIO

Repositorio dedicado a documentar cómo lograr GPU passthrough en una laptop ASUS TUF GAMING F15 con CachyOS, tanto para respaldar mi propia configuración como para compartir la solución con la comunidad.

> **Nota del autor:** Esta guía describe mi experiencia personal configurando GPU passthrough. Nació de un día de aburrimiento y curiosidad. Si tu hardware es similar, puede servirte como referencia, pero recuerda que cada sistema es único.

---

## 📋 Tabla de Contenidos

1. [Requisitos Previos](#-requisitos-previos)
2. [Introducción al Sistema](#-introducción-al-sistema)
3. [Configuración Paso a Paso](#-configuración-paso-a-paso)
  - [Paso 1: Instalación de supergfxd](#paso-1-instalación-de-supergfxd)
  - [Paso 2: Preparación de vBIOS](#paso-2-preparación-de-vbios)
  - [Paso 3: Crear Batería Virtual](#paso-3-crear-batería-virtual)
  - [Paso 4: Creación de la VM](#paso-4-creación-de-la-vm)
  - [Paso 5: Configuración de GPU Passthrough](#paso-5-configuración-de-gpu-passthrough)
  - [Paso 6: Configuración de Hooks](#paso-6-configuración-de-hooks)
  - [Paso 7: Instalación de Drivers](#paso-7-instalación-de-drivers)
4. [Pasos Adicionales](#-pasos-adicionales)
5. [Conclusión](#-conclusión)
6. [Créditos y Agradecimientos](#-créditos-y-agradecimientos)
7. [Notas Finales](#-notas-finales)

---

## 🔧 Requisitos Previos

<details>
<summary>Ver requisitos completos</summary>

Antes de comenzar, asegúrate de tener preparado lo siguiente:

### Hardware
- **Laptop:** ASUS TUF GAMING F15 con arquitectura de gráficos híbrida (iGPU Intel + dGPU NVIDIA)
- **Monitor externo:** Obligatorio (esta guía no cubre configuración para pantalla integrada)

### Software
- **Sistema Operativo:** CachyOS con KDE Plasma
  - *Nota:* Puede funcionar en otras distribuciones, pero esta es la configuración probada
- **Herramientas de virtualización:**
  - QEMU/KVM
  - Virt-Manager
  - supergfxctl (para gestión de gráficos híbridos)
- **ISOs necesarias:**
  - Windows 10 IoT LTSC (recomendado por ser liviano y sin bloatware)
  - Última versión de [VirtIO drivers](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/)

### Actitud
- **Paciencia:** El proceso puede tomar tiempo, especialmente sin experiencia previa
  - *En mi caso:* Me tomó 2 días hacer funcionar todo correctamente

</details>

---

## 💡 Introducción al Sistema

La ASUS TUF GAMING F15 utiliza una arquitectura de gráficos híbrida:
- **iGPU Intel:** Integrada en el procesador
- **dGPU NVIDIA:** Tarjeta gráfica dedicada

**Objetivo:** Aislar la tarjeta NVIDIA para asignarla exclusivamente a una máquina virtual mediante VFIO.

### ✨ Ventaja de CachyOS

Una de las grandes ventajas de utilizar CachyOS es que **gran parte de la configuración base ya está lista**. A diferencia de otras distribuciones donde es necesario:
- Modificar parámetros del kernel manualmente
- Realizar ajustes complejos en la BIOS
- Configurar módulos desde cero

CachyOS viene preinstalado con muchas optimizaciones necesarias para virtualización y VFIO.

---

## 🚀 Configuración Paso a Paso

### Paso 1: Instalación de supergfxd

<details>
<summary>Ver detalles de instalación</summary>

`supergfxd` es una herramienta que facilita la gestión de gráficos híbridos en laptops.

#### Opciones de instalación:
- Repositorios oficiales de CachyOS
- AUR (Arch User Repository)
- Repositorio de asus-linux
- Compilar desde el [repositorio oficial en GitLab](https://gitlab.com/asus-linux/supergfxctl)

#### Habilitar el servicio

```bash
sudo systemctl enable supergfxd
sudo systemctl start supergfxd
```
> Habilitar y arrancar el servicio genera la configuración inicial, pero debes activar manualmente el modo VFIO en **`/etc/supergfxd.conf`**

#### Configuración recomendada

En la carpeta **`docs/`** de este repositorio encontrarás mi archivo `supergfxd.conf` como referencia.

El detalle más importante para está configuración es cambiar `hotplug_type` de "Asus" a "Std". El modo Asus apaga la tarjeta tan agresivamente que desaparece del bus PCI, haciendo imposible el passthrough.

**Recomendación fuerte:** Usa la misma configuración que funcionó en mi sistema. Como dicen: *"Si algo funciona, no lo toques"*.

#### Reiniciar el sistema

```bash
sudo reboot
```

> Es más seguro reiniciar completamente que solo reiniciar el servicio.

</details>

---

### Paso 2: Preparación de vBIOS

<details>
<summary>Ver detalles de preparación de vBIOS</summary>

Este paso es crucial para evitar el temido **Error 43** de NVIDIA en entornos virtualizados.

#### ¿Por qué necesitamos esto?
La vBIOS sirve para que la máquina virtual sepa como inicializar la GPU correctamente para evitar el error 43.

#### Descarga de vBIOS

Descarga una vBIOS compatible con tu GPU desde [TechPowerUp](https://www.techpowerup.com/vgabios/).

Para **RTX 3050 Laptop**, utilicé [esta vBIOS específica](https://www.techpowerup.com/vgabios/253414/253414.rom).

#### Edición hexadecimal

Es necesario **eliminar el encabezado** añadido por la herramienta de extracción:

1. Abre el archivo `.rom` con un editor hexadecimal (como `hexedit` o `GHex`)
2. Busca la primera aparición de la cadena **`55 AA`**
3. **Elimina todo el contenido anterior** a `55 AA` (el header de NVFlash)
4. Guarda el archivo

**¿Por qué?** El encabezado contiene metadatos que no son parte del firmware real y pueden interferir. QEMU necesita que la ROM comience con la firma estándar `55 AA`.

#### Ubicación del archivo

Guarda la vBIOS parcheada con:

```bash
sudo cp rtx3050_patched.rom /usr/share/vgabios/rtx3050_patched.rom
```

> Puedes usar otra ubicación si prefieres, pero recuerda la ruta para pasos posteriores y asegúrate de que QEMU tenga permisos de lectura.

</details>

---

### Paso 3: Crear Batería Virtual

<details>
<summary>Ver detalles de creación de batería virtual</summary>

La GPU NVIDIA detectará que no hay batería en el sistema virtual y lanzará el Error 43. Para evitarlo, crearemos una batería falsa.

#### Usar el script incluido

En la carpeta **`scripts/`** encontrarás `battery.sh`.

```bash
# Dar permisos de ejecución
chmod +x battery.sh

# Ejecutar con sudo (necesario para mover archivos a /usr/share)
sudo ./battery.sh
```

El script genera un archivo **`SSDT1.dat`** y lo mueve automáticamente a `/usr/share/vgabios/`.

> Si usaste un directorio diferente en el paso anterior, edita la ruta dentro del script antes de ejecutarlo.

</details>

---

### Paso 4: Creación de la VM
<details>
<summary>Ver detalles de creación de la VM</summary>

Para facilitarte la vida, he incluido mi archivo XML completo y funcional de mi máquina virtual de Windows 10 en este repositorio. Puedes usarlo como base e ir ajustándolo según tus necesidades.

📂 **Archivo:** [`xml/win10.xml`](./xml/win10.xml)

> Puedes copiar este contenido y pegarlo directamente en la pestaña "XML" de Virt-Manager (reemplazando todo) antes de iniciar la instalación, asegurándote de corregir cualquier ruta específica (como la del disco duro).

De todas formas aquí te dejo los pasos detallados para crear la VM desde cero:

#### Proceso inicial

1. Abre **Virt-Manager**
2. Crea una nueva máquina virtual seleccionando la ISO de **Windows 10 IoT LTSC** dejandole el nombre por defecto que es `win10`.
3. **Antes de finalizar:** Marca la opción **"Personalizar la configuración antes de la instalación"**

#### CPU y Memoria
Asigna recursos adecuados según tu hardware:
- **CPU:** 4-6 núcleos (dependiendo de tu CPU)
- **Memoria:** 8-16 GB (según disponibilidad)


En la condfiguración de la CPU:
Desmarcar "copiar configuración de la CPU del anfitrión (host-passthrough)"
Especificar modelo: `host-passthrough` manualmente.
Habilitar `Activar las mitigaciones de fallos de seguridad disponibles para la CPU` en la VM para evitar vulnerabilidades.

Topología:
Marcar `Establecer manualmente la topología de la CPU`
Especificar números de sockets, núcleos y threads según tu configuración de CPU.
en mi caso: 1 socket, 3 núcleos, 2 threads (6 núcleos lógicos en total).

#### Configuración de dispositivos

Cambia los siguientes dispositivos a **VirtIO** para mejor rendimiento:
- **Disco duro:** VirtIO
- **Red:** VirtIO

#### Añadir ISO de VirtIO

Agrega un **CD-ROM adicional** y monta la ISO de VirtIO para instalar drivers durante la instalación de Windows.

> En este punto NO agregues ningún dispositivo PCI ni modifiques el XML todavía.

#### Instalación de Windows

Durante la instalación de Windows:

1. Cuando llegues a la selección de disco, Windows no detectará ningún disco (porque usa VirtIO)
2. Haz clic en **"Cargar controlador"**
3. Navega al CD-ROM de VirtIO
4. Instala los drivers desde las siguientes carpetas:
    - **`viostor`** → Para el disco duro
    - **`NetKVM`** → Para acceso a red

Completa la instalación de Windows normalmente.

</details>

---

### Paso 5: Configuración de GPU Passthrough

<details>
<summary>Ver detalles de configuración de GPU Passthrough</summary>

Una vez que Windows esté instalado y funcionando, pasaremos la GPU NVIDIA a la VM.

#### Cambiar modo de gráficos

```bash
# Cambiar a modo Integrated
supergfxctl -m Integrated

# Cerrar sesión y volver a iniciar
# Luego cambiar a modo VFIO
supergfxctl -m Vfio
```

Esto libera la GPU NVIDIA para ser asignada a la VM.

#### Identificar grupos IOMMU

Ejecuta el script que deje en **`scripts/`** llamado `iommu.sh`:

```bash
chmod +x iommu.sh
sudo ./iommu.sh
```

Busca el grupo que contiene:
- La GPU NVIDIA
- El controlador de audio HDMI/DP asociado

#### Agregar dispositivos PCI

En Virt-Manager:

1. **Apaga la VM**
2. Edita la configuración de la máquina
3. Agrega nuevo hardware → **PCI Host Device**
4. Selecciona los dispositivos del grupo IOMMU de la GPU NVIDIA (GPU + Audio)

#### Editar XML de la GPU

Edita el XML del dispositivo PCI de la GPU para especificar la vBIOS parcheada:

```xml
<hostdev mode='subsystem' type='pci' managed='yes'>
     <source>
          <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
     </source>
     <rom bar='off' file='/usr/share/vgabios/rtx3050_patched.rom'/>
     <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0' multifunction='on'/>
</hostdev>
```
> - Reemplaza la ruta del archivo con tu ubicación
> - `rom bar='off'` es **importante**: hace que QEMU cargue la vBIOS personalizada

#### Modificar el dominio

Al inicio del XML, reemplaza el `<domain type='kvm'>` por:

```xml
<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
```

#### Añadir SMBIOS

Justo después de la etiqueta `<os>`, agrega:

```xml
<smbios mode='host'/>
</os>
```

Esto hace que la VM vea los datos de hardware/BIOS del host (fabricante, modelo, números de serie), ayudando a evitar detección de virtualización.

#### Otros parametros de ocultamiento de virtualización
Agrega dentro de la etiqueta `<hyperv>`, si no existe ya:

```xml
<hyperv>
 <vendor_id state="on" value="0123456789ab"/>
</hyperv>
```

Agregar esto ayuda a ocultar la presencia de virtualización a la GPU NVIDIA.

Además, asegúrate de que la sección `<features>` incluya:

```xml
<features>
    <kvm>
        <hidden state="on"/>
    </kvm>
</features>
```

Esto oculta aún más la presencia de KVM al sistema invitado y nos aseguramos que Nvidia no detecte que estamos en una VM.

#### Argumentos QEMU

Al final del XML, **antes de** `</domain>`, agrega:

```xml
<qemu:commandline>
     <qemu:arg value='-global'/>
     <qemu:arg value='vfio-pci.x-pci-sub-vendor-id=0x1043'/>
     <qemu:arg value='-global'/>
     <qemu:arg value='vfio-pci.x-pci-sub-device-id=0xNNNN'/>
     <qemu:arg value='-acpitable'/>
     <qemu:arg value='file=/usr/share/vgabios/SSDT1.dat'/>
</qemu:commandline>
</domain>
```

**¿Qué hace esto?**
- `0x1043`: Vendor ID de ASUS
- `0xNNNN`: Device ID específico de la RTX 3050 Laptop
- Carga la batería virtual (`SSDT1.dat`)

> Verifica tu Device ID específico usando `lspci -n` en el host. Puede variar según el modelo exacto.

#### Limpiar dispositivos innecesarios

Elimina los siguientes dispositivos que Virt-Manager añade automáticamente:
- ❌ Sonido ich9 (opcional, lo añadiremos después si es necesario)
- ❌ Consola 1
- ❌ Canal Spice (déjalo si planeas usar Looking Glass, pero esta guía no lo cubre)
- ❌ Redirecciones USB (las pasaremos directamente después)

Guarda los cambios y **cierra Virt-Manager**.

</details>

---

### Paso 6: Configuración de Hooks

<details>
<summary>Ver detalles de configuración de Hooks</summary>

Los hooks de QEMU permiten ejecutar scripts automáticamente al iniciar/detener la VM.

#### Copiar estructura de hooks

En este repositorio encontrarás la carpeta **`qemu.d/`**. Cópiala a `/etc/libvirt/hooks/`:

```bash
sudo cp -r qemu.d /etc/libvirt/hooks/
```

#### Configurar variables de la VM

Edita el archivo **`/etc/libvirt/hooks/qemu.d/win10/vm-vars.conf`** y ajusta:

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `LOGGED_IN_USERNAME` | Tu nombre de usuario en Linux | `"tuusuario"` |
| `LOGGED_IN_USERID` | Tu ID de usuario (`id -u`) | `"1000"` |
| `VM_MEMORY` | RAM dedicada a la VM en KiB | `8388608` (8 GB) |
| `VM_ISOLATED_CPUS` | CPUs asignados a la VM | `"2-7"` |
| `SYS_TOTAL_CPUS` | CPUs totales del sistema | `"0-15"` |

**Mi configuración (Intel i5-12500H):**
- Total de CPUs: 16 (0-15)
- Asignados a VM: 2-7 (núcleos de rendimiento)

#### Establecer permisos correctos

```bash
sudo chown -R root:root /etc/libvirt/hooks/qemu.d
sudo chmod -R 755 /etc/libvirt/hooks/qemu.d
sudo chmod 644 /etc/libvirt/hooks/qemu.d/win10/vm-vars.conf
```

**Permisos requeridos:**
- `qemu.d/`: `drwxr-xr-x` (755)
- `vm-vars.conf`: `-rw-r--r--` (644)

</details>

---

### Paso 7: Instalación de Drivers

<details>
<summary>Ver detalles de instalación de drivers</summary>

¡Momento de la verdad! 🎉

#### Iniciar la VM

Inicia la máquina virtual desde Virt-Manager.

> Si la VM arranca correctamente, Ya llevas el **80% del camino**. Si hay errores, revisa cuidadosamente cada paso anterior.

#### Instalar driver de NVIDIA

Dentro de Windows:

1. Descarga el último driver de NVIDIA
2. Selecciona **"Instalación Limpia"**
3. Reinicia la VM después de la instalación

#### Verificar funcionamiento

Abre el **Administrador de Dispositivos** de Windows y verifica:
- ✅ La GPU NVIDIA aparece sin errores
- ✅ No hay signo de exclamación amarillo en la tarjeta gráfica

</details>

---

## 🔊 Pasos Adicionales

<details>
<summary>Agregar audio virtual a la VM</summary>

> Si no tienes sonido en la vm, sigue estos pasos:

#### 1. Verificar membresía en grupo KVM

```bash
groups
```

Si no estás en el grupo `kvm`:

```bash
sudo usermod -aG kvm $USER
```

Luego **reinicia el sistema** o cierra sesión.

#### 2. Configurar QEMU para audio

Edita **`/etc/libvirt/qemu.conf`**:

```conf
# Cambiar usuario (busca la línea comentada)
user = "TU_USUARIO"

# Cambiar grupo
group = "kvm"

# Habilitar audio del host
nographics_allow_host_audio = 1
```

#### 3. Reiniciar servicio

```bash
sudo systemctl restart libvirtd
```

#### 4. Configurar dispositivo de audio

En Virt-Manager, edita la VM y agrega (o modifica) el dispositivo de sonido ich9.

En el XML de la VM, dentro de `<devices>`, añade:

```xml
<audio id='1' type='pulseaudio' serverName='/run/user/TU_USERID/pulse/native'/>
<sound model='ich9'>
     <audio id='1'/>
</sound>
```

Reemplaza **`TU_USERID`** con tu ID de usuario.

Para obtener tu ID de usuario, ejecuta:

```bash
id -u
```

#### 5. Verificar

Inicia la VM y verifica que:
- ✅ El audio funciona correctamente

> **Experiencia personal:** En mi caso, esto también resolvió el problema del signo de exclamación en el driver de audio NVIDIA (High Definition Audio) por lo tanto se puede enviar audio directo al HDMI. No entiendo por qué se arregló, pero funcionó.

</details>

---

## 🎯 Conclusión

Mis pasos fueron muy específicos para mi hardware y configuración de software, pero espero que esta guía te sirva como referencia sólida para configurar VFIO en tu ASUS TUF GAMING F15.

**Recuerda:** Cada sistema es diferente. Adapta los pasos según tu configuración específica y no tengas miedo de experimentar.

---

## 🙏 Créditos y Agradecimientos

<details>
<summary>Ver créditos completos</summary>

Esta guía no habría sido posible sin el trabajo y la documentación de:

### Proyectos y Comunidades
- **[CachyOS](https://cachyos.org/)** - Por facilitar la configuración base y tener optimizaciones pre-instaladas
- **[Comunidad VFIO](https://www.reddit.com/r/VFIO/)** - Por su valiosa documentación y soporte continuo
- **[ASUS Linux](https://asus-linux.org/)** - Por su excelente [guía en inglés](https://asus-linux.org/guides/vfio-guide/) que sirvió como base parcial

### Recursos Técnicos
- **[TechPowerUp](https://www.techpowerup.com/vgabios/)** - Por proporcionar vBIOS parcheadas
- **[Arch Wiki](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)** - Por su completa guía de referencia sobre VFIO
- **[Post de éxito en Reddit](https://www.reddit.com/r/VFIO/comments/hx5j8q/success_with_laptop_gpu_passthrough_on_asus_rog/)** - Experiencias compartidas que ayudaron con configuraciones específicas
- **[Post sobre batería virtual](https://www.reveddit.com/v/VFIO/comments/ebo2uk/nvidia_geforce_rtx_2060_mobile_success_qemu_ovmf/)** *(eliminado, pero visible en Reveddit)* - Solución crucial para el Error 43

### Herramientas
- **Gemini AI** - Por ayudarme a resolver problemas durante el proceso
- **GitHub** - Por alojar este repositorio y permitir compartir conocimiento

### Agradecimientos especiales
- **A Nvidia** - Por hacer tanto drama con sus drivers y obligarme a buscar soluciones por todos lados.
- **A mí mismo** - Por tener la paciencia de investigar y experimentar durante 2 días hasta lograr que todo funcionara

</details>

---

## 📝 Notas Finales

> - Esta guía asume conocimiento **básico** de Linux, QEMU/KVM y virtualización
> - Los pasos pueden variar dependiendo de tu configuración específica de hardware y software
> - **Siempre haz copias de seguridad** antes de realizar cambios significativos en tu sistema
> - El GPU passthrough en laptops es más complejo que en desktops debido a la arquitectura híbrida

---

<div align="center">

**Hecho con ☕ y muchas horas de experimentación**

</div>