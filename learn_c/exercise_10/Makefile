COMPILER = gcc
CFLAGS = -Wall -g
TARGET = myprogram
SRCS = ex10.c 
OBJS = $(SRCS:.c=)

comp:
	${COMPILER} $(SRCS) -o $(OBJS)

run: 
	./${OBJS}

clean:
	rm ./${OBJS} -rf

debug:
	valgrind ./${OBJS}
