MCU := F350
PART := GD32F350

TARGETS_$(MCU) := $(call get_targets,$(MCU))

HAL_FOLDER_$(MCU) := $(HAL_FOLDER)/$(call lc,$(MCU))

MCU_$(MCU) := -mcpu=cortex-m4 -mthumb
ifeq ($(F350_STANDALONE),1)
LDSCRIPT_$(MCU) := $(HAL_FOLDER_$(MCU))/gd32f350x8_standalone.ld
else
LDSCRIPT_$(MCU) := $(HAL_FOLDER_$(MCU))/gd32f350x8_flash.ld
endif

SRC_BASE_DIR_$(MCU) := \
	$(HAL_FOLDER_$(MCU))/Drivers/GD32F3x0_standard_peripheral/Source \
	$(HAL_FOLDER_$(MCU))/Startup

SRC_DIR_$(MCU) := $(SRC_BASE_DIR_$(MCU)) \
	$(HAL_FOLDER_$(MCU))/Src

CFLAGS_$(MCU) += \
	-I$(HAL_FOLDER_$(MCU))/Inc \
	-I$(HAL_FOLDER_$(MCU))/Drivers/CMSIS/Include \
	-I$(HAL_FOLDER_$(MCU))/Drivers/CMSIS/Core/Include \
	-I$(HAL_FOLDER_$(MCU))/Drivers/GD32F3x0_standard_peripheral/Include

CFLAGS_$(MCU) += \
	-DGD32$(MCU) \
	-D$(PART) \
	-DUSE_STDPERIPH_DRIVER

ifeq ($(F350_STANDALONE),1)
CFLAGS_$(MCU) += -DVECT_TAB_OFFSET=0
endif


SRC_$(MCU) := $(foreach dir,$(SRC_DIR_$(MCU)),$(wildcard $(dir)/*.[cs]))
