#! /bin/bash
readonly HOST="https://api.vk.com/method"
readonly BOT_TOKEN="token"
readonly VERSION="5.103"
readonly GROUP="group id"
readonly ERROR_MESSAGE="Операция превысила предусмотренный лимит времени выполнения."
readonly GET_SERVER="$HOST/groups.getLongPollServer?\
v=$VERSION\
&access_token=$BOT_TOKEN\
&group_id=$GROUP"
readonly SEND_MESSAGE="$HOST/messages.send?v=$VERSION\
&access_token=$BOT_TOKEN\
&random_id=0"
readonly MACROS=$(< MACROS.bc)

function main ()
{
	MAIN=$(wget -cq "$GET_SERVER" -O - | jq '.')
	RESPONSE=$(echo "$MAIN" | jq '.response')
	SERVER=$(echo "$RESPONSE" | jq -r '.server')
	KEY=$(echo "$RESPONSE" | jq -r '.key')
	TS=$(echo "$RESPONSE" | jq -r '.ts')

	while [ true ]
	do
		LONGPOLL_REQUEST=$(wget -cq "$SERVER?act=a_check&key=$KEY&ts=$TS&wait=25" -O - | jq '.')
		### ERROR OVERRIDE ###
		if [ $(echo "$LONGPOLL_REQUEST" | jq -r '.failed') == "2" ]
		then
			MAIN=$(wget -cq "$GET_SERVER" -O - | jq '.')
			KEY=$(echo "$MAIN" | jq -r '.response.key')
		elif [ $(echo "$LONGPOLL_REQUEST" | jq -r '.failed') == "3" ]
		then
			MAIN=$(wget -cq "$GET_SERVER" -O - | jq '.')
			KEY=$(echo "$MAIN" | jq -r '.response.key')
			TS=$(echo "$MAIN" | jq -r '.response.ts')
		fi

		UPDATES=$(echo "$LONGPOLL_REQUEST" | jq '.updates')
		TS=$(echo "$LONGPOLL_REQUEST" | jq -r '.ts')
		LENGTH=$(echo "$UPDATES" | jq -r '. | length')

		if [ $LENGTH == 0 ]
		then
			continue
		fi

		LENGTH=$(($LENGTH - 1))

		for ((VALUE=0; VALUE<=LENGTH; VALUE++))
		do
			UPDATE=$(echo "$UPDATES" | jq ".[$VALUE]")
			TYPE=$(echo "$UPDATE" | jq -r '.type')
			if [ $TYPE == "message_new" ]
			then
				FROM_ID=$(echo "$UPDATE" | jq -r '.object.message.from_id')
				PEER_ID=$(echo "$UPDATE" | jq -r '.object.message.peer_id')
				TEXT=$(echo "$UPDATE" | jq -r '.object.message.text')

				echo "$TEXT"
				if [[ $TEXT == expr* ]]
				then
					REGEX='expr\ (.+).*'
					### CALCULATE AN EXPRESSION ###
					if [[ $TEXT =~ $REGEX ]]
					then
						EXPRESSION=${BASH_REMATCH[1]}
						echo "Got an expression: $EXPRESSION"
						RESULT=$(echo "$MACROS$EXPRESSION" | timeout 4 bc -l 2> ./ERROR.txt)
						TIMEOUT_STATE=$?
						SYNTAX_ERROR=$(< ./ERROR.txt)
						MESSAGE=$RESULT

						if [ $TIMEOUT_STATE -ne 0 ]
						then
							MESSAGE=$ERROR_MESSAGE
						fi

						if [[ $SYNTAX_ERROR ]]
						then
							echo "$SYNTAX_ERROR"
							MESSAGE="При выполнении возникли следующие ошибки:"$'\n'"$SYNTAX_ERROR"
						fi
					fi
					MESSAGE_SENT=$(wget -cq "$SEND_MESSAGE&peer_id=$PEER_ID&message=$MESSAGE" -O -)
				elif [[ $TEXT == random* ]]
				then
					REGEX_RAND='random\ ([1248]$)'
					REGEX_RAND_OVERLOAD='random\ (9|[1-9][0-9]+)'
					### GENERATE TRUE (not) RANDOM NUMBERS ###
					if [[ $TEXT =~ $REGEX_RAND ]]
					then
						RANDOM_NUMBER_SIZE=${BASH_REMATCH[1]}
						RANDOM_NUMBER=$(od -vAn -N$RANDOM_NUMBER_SIZE -tu$RANDOM_NUMBER_SIZE < /dev/urandom)
						MESSAGE=$RANDOM_NUMBER
					elif [[ $TEXT =~ $REGEX_RAND_OVERLOAD ]]
					then
						MESSAGE="Случайные числа размером более 8 байт не поддерживаются."
					else
						MESSAGE="Задан неверный размер числа. Доступны числа размером 1, 2, 4 и 8 байт."
					fi
					MESSAGE_SENT=$(wget -cq "$SEND_MESSAGE&peer_id=$PEER_ID&message=$MESSAGE" -O -)	
				fi
				TEXT=0
			fi
		done
	done
}

main
