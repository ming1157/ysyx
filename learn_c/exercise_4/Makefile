COMPILER = gcc
CFLAGS = -Wall -g
TARGET = myprogram
SRCS = ex4.c 
OBJS = $(SRCS:.c=)

comp:
	${COMPILER} $(SRCS) -o $(OBJS)

clean:
	rm ./${OBJS} -rf

debug:
	valgrind ./${OBJS}
