#if defined _k1_playertag_included   
    #endinput 
#endif 
#define _k1_playertag_included    

/**
 *	Узнать скрыт ли админ.
 *	-
 * @param client			id клиента
 *	-
 * @return					true - да
 * 							false - нет
*/
native bool K1_PlayerIncog(int client);
