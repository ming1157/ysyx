#include<stdio.h>

int main(int argc, char *argv[]){
  // go through each string in argv
  
  int i = 0;
  
  if(argc == 1){
     printf("You only have one argument.You such.\n");
   } else if (argc > 1 && argc <4){
     printf("Here's your arguments:\n");
     for(i=0;i<argc;i++){
        printf("%s",argv[i]);
     }
     printf("\n");
   } else{
     printf("You have too many arguments. You suck.\n");
   }

  return 0;
}


