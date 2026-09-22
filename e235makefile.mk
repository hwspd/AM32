MCU := E235
PART := GD32E235

TARGETS_$(MCU) := $(call get_targets,$(MCU))
HAL_FOLDER_$(MCU) := $(HAL_FOLDER)/$(call lc,$(MCU))
MCU_$(MCU) := -mfloat-abi=soft -mthumb -mcpu=cortex-m23
LDSCRIPT_$(MCU) := $(HAL_FOLDER_$(MCU))/gd32e235x8_flash.ld

SRC_DIR_$(MCU) := \
	$(HAL_FOLDER_$(MCU))/Drivers/GD32E23x_standard_peripheral/Source \
	$(HAL_FOLDER_$(MCU))/Src

CFLAGS_$(MCU) += \
	-I$(HAL_FOLDER_$(MCU))/Inc \
	-I$(HAL_FOLDER_$(MCU))/Drivers/CMSIS/Include \
	-isystem $(HAL_FOLDER_$(MCU))/Drivers/CMSIS/Core/Include \
	-I$(HAL_FOLDER_$(MCU))/Drivers/GD32E23x_standard_peripheral/Include \
	-D$(PART) -DUSE_STDPERIPH_DRIVER

ifeq ($(E235_STANDALONE),1)
CFLAGS_$(MCU) += -DVECT_TAB_OFFSET=0
LDFLAGS_$(MCU) += -Wl,--defsym=__app_start=0x08000000
endif

# The SDK GCC startup has an uppercase .S suffix and needs preprocessing.
SRC_$(MCU) := $(foreach dir,$(SRC_DIR_$(MCU)),$(wildcard $(dir)/*.[cs])) \
	$(HAL_FOLDER_$(MCU))/Startup/startup_gd32e23x.S
