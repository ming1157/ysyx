COMPILER = gcc
CFLAGS = -Wall -g
TARGET = myprogram
SRCS = ex1.c 
OBJS = $(SRCS:.c=)

compile:
	${COMPILER} $(SRCS) -o $(OBJS)


clean:
	rm ./${OBJS} -rf
