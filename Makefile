ifeq ($(FPGA), "9k")
include Makefile9k.mk
else
include Makefile20k.mk
endif
