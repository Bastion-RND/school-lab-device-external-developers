# Функция для выполнения запроса и получения URL аудио файла
function GetAudioURL {
    param (
        [string]$url
    )

    $response = Invoke-WebRequest -Uri $url -Method Get

    $jsonContent = $response.Content | ConvertFrom-Json

    # Фильтруем элементы с type = "audio"
    $audioReleases = $jsonContent.releases | Where-Object { $_.type -eq "audio"}

    if ($audioReleases.Count -gt 0) {
        # Находим запись с самым последним значением поля "date"
        $latestAudioRelease = $audioReleases | Sort-Object -Property date -Descending | Select-Object -First 1
        
        return $latestAudioRelease.file
    } elseif (-not ($audioReleases -is [array])) {
        # Проверка на то, что объект один, а не списком
        return $audioReleases.file
    } else {
        Write-Host "Нет доступных аудио-релизов или релизов"
        exit
    }
}

# Функция для загрузки файла с выводом прогресса
function DownloadFile {
    param (
        [string]$fileUrl,
        [string]$fileName
    )

    # Скачиваем файл
    Write-Host "Скачивание файла..."
    Invoke-WebRequest -Uri $fileUrl -OutFile $fileName -Verbose

    # Проверяем успешность загрузки файла
    if ($?) {
        Write-Host "Файл $fileName загружен."
    } else {
        Write-Host "Ошибка при загрузке файла."
        exit
    }
}

# Функция для вывода списка доступных USB-накопителей
function Get-USBDrives {
    $usbDrives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
    
    if ($usbDrives.Count -eq 0) {
        Write-Host "Доступных накопителей не обнаружено."
        exit
    }
    
    $driveLetters = $usbDrives.DeviceID

    # Выбрать накопитель из списка
    $selectedDrive = $driveLetters | Out-GridView -Title "Выберите букву выбранного USB-накопителя" -OutputMode Single

    if (-not $selectedDrive) {
        Write-Host "Выбор USB-накопителя отменен."
        exit
    }

    return $selectedDrive.TrimEnd(":")
}

function Format-USBDrive {
    param (
        [string]$driveLetter
    )
    $driveL = $driveLetter + ":"
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$driveL'"

    # Проверяем, существует ли информация о диске
    if (-not $disk) {
        Write-Host "Диск $driveLetter не найден."
        exit
    }

    # Переводим размер из байтов в гигабайты
    $diskSizeGB = $disk.Size / 1GB

    # Проверяем размер диска
    if ($diskSizeGB -lt 2.7) {
        Write-Output "Размер диска $driveLetter меньше 2.7 ГБ. Необходимо больше места для создания разделов"
        exit
    }

    Add-Type -AssemblyName System.Windows.Forms
    $result = [System.Windows.Forms.MessageBox]::Show("Вы действительно хотите создать разделы из $driveLetter в формате FAT32? Все данные на накопителе будут удалены", "Подтверждение", [System.Windows.Forms.MessageBoxButtons]::YesNo)

    Write-Host "Вы действительно хотите создать разделы из $driveLetter в формате FAT32?"
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        $partition = Get-Partition -DriveLetter $driveLetter
        if (-not $partition) {
            Write-Host "Диск $driveLetter не найден."
            exit
        }
        
        $diskNumber = $partition.DiskNumber

        # Находим первую доступную букву диска, которая ещё не используется
        $existingDriveLetters = Get-WmiObject Win32_LogicalDisk | Select-Object -ExpandProperty DeviceID
        $letter1 = [char]([int][char]$existingDriveLetters[-1].Trim(':') + 1)
        $letter2 = [char]([int][char]$existingDriveLetters[-1].Trim(':') + 2)
        $letter3 = [char]([int][char]$existingDriveLetters[-1].Trim(':') + 3)

        # Отформатируем диск с помощью diskpart
        $diskPartScript = @"
            select disk $diskNumber
            clean
            convert mbr
            create partition primary size=512
            format fs=FAT32 label="audio" quick
            assign letter=$letter1
            create partition primary size=2048
            format fs=FAT32 label="firmware" quick
            assign letter=$letter2
            create partition primary
            format fs=FAT32 label="logs" quick
            assign letter=$letter3
"@
        $diskPartScript | diskpart | Out-Null

        Write-Host "USB-накопитель $driveLetter отформатирован и разделен на три части."
        return $letter1
    } else {
        Write-Host "Отменено пользователем."
        exit
    }
}

function ExtractToUSB {
    param (
        [string]$fileName,
        [string]$driveLetter
    )

    if (($driveLetter -eq $null) -or ($driveLetter -eq "") -or ($driveLetter.Length -gt 1)) {
        $driveLetter = Get-USBDrives
    }

    Expand-Archive -Path $fileName -DestinationPath ($driveLetter + ":\") -Force
    
}


if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Скрипт необходимо запускать с правами администратора"
    exit
}

# Указываем URL для GET-запроса
$url = "https://school-lab-updater.bast.ru/api/v1/releases"
# Указываем имя файла для сохранения
$fileName = ".\school_lab_audio.zip"

# Проверяем наличие файла "school_lab_audio" в папке со скриптом
$fileExists = Test-Path -Path $fileName

# Если файл уже существует, выводим сообщение и завершаем скрипт
if ($fileExists) {
    Write-Host "Файл уже существует: school_lab_audio.zip"
} else {
    # Получаем URL аудио файла
    $audioFileUrl = GetAudioURL -url $url
    # Загружаем файл
    DownloadFile -fileUrl $audioFileUrl -fileName $fileName
}

# Получаем список доступных USB-накопителей
$selectedDrive = Get-USBDrives


# Форматируем выбранный накопитель
$newDriveLetter = Format-USBDrive -driveLetter $selectedDrive

# Разархивируем аудио файл в первый раздел выбранного накопителя
#Expand-Archive -Path $fileName -DestinationPath ($letter1 + ":\") -Force
ExtractToUSB -fileName $fileName -driveLetter $newDriveLetter


