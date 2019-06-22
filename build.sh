#!/usr/bin/env bash

function checking() {
   [[ -z "${bottoken}" ]] && echo "Telegram API_KEY not defined, exiting!" && exit 1
   [[ -z "${GITHUB_AUTH_TOKEN}" ]] && echo "GITHUB_AUTH_TOKEN not defined, exiting!" && exit 1

   if [ -z "$KERNEL_PATH" ]; then
      KERNEL_PATH=$(pwd)
   else
      export KERNEL_PATH
   fi 
}

function exports() {
   export KBUILD_BUILD_USER="Nano-developers"
   export KBUILD_BUILD_HOST="Nano-Team"
   export ARCH=arm64
   export SUBARCH=arm64
   export PATH=$KERNEL_PATH/Toolchain/bin:$PATH
   export OUT_PATH="out/arch/arm64/boot"
   export anykernel_link=$(jq -r '.anykernel_url' $KERNEL_PATH/extras/information.json)
   export toolchain_link=$(jq -r '.toolchain_url' $KERNEL_PATH/extras/information.json)
   export group_id=$(jq -r '.group_id' $KERNEL_PATH/extras/information.json)
   export channel_id=$(jq -r '.channel_id' $KERNEL_PATH/extras/information.json)
}

function sendTG() {
   curl -s "https://api.telegram.org/bot${bottoken}/sendmessage" --data "text=${*}&chat_id="$group_id"6&parse_mode=Markdown" > /dev/null
}

function clone() {
	git clone --depth=1 --no-single-branch $toolchain_link $KERNEL_PATH/Toolchain
}
 
function build() {  
   for ((i=0;i<=1;i++));
   do 
      rm -rf $KERNEL_PATH/anykernel
      rm -rf $KERNEL_PATH/out
      git clone --depth=1 --no-single-branch $anykernel_link $KERNEL_PATH/anykernel2
      DEFCONFIG=$(jq -r --argjson i "$i" '.[$i].defconfig' $KERNEL_PATH/extras/supported_version.json)
	  if [ -f $KERNEL_PATH/arch/arm64/configs/$DEFCONFIG ]
	  then 
         export TYPE=$(jq -r --argjson i "$i" '.[$i].type' $KERNEL_PATH/extras/supported_version.json)
		 export BASE_URL=$(jq -r '.base_url' $KERNEL_PATH/extras/information.json)
		 export NUM=$(jq -r --argjson i "$i" '.[$i].version' $KERNEL_PATH/extras/supported_version.json)
		 export BUILD_DATE="$( date +"%Y%m%d-%H%M" )"
		 export FILE_NAME="Nano_Kernel-rosy-$BUILD_DATE_${TYPE}-v$NUM.zip"
		 export FILE_NAME_${TYPE}="$FILE_NAME"
		 export LINK="${BASE_URL}/${TYPE}/${FILE_NAME}"		
		 export LINK_${TYPE}="$LINK"
       else
		 sendTG "Defconfig Mismatch"
		 echo "Exiting in 5 seconds"
		 sleep 5
		 exit
	   fi

	   make O=out $DEFCONFIG
	   BUILD_START=$(date +"%s")
	   make -j${JOBS} O=out \
	   CROSS_COMPILE="$KERNEL_PATH/Toolchain/bin/aarch64-linux-android-" 
	   BUILD_END=$(date +"%s")
	   BUILD_TIME=$(date +"%Y%m%d-%T")
	   DIFF=$((BUILD_END - BUILD_START))	

	   if [ -f $KERNEL_PATH/$OUT_PATH/Image.gz-dtb ]
	   then 
	      sendTG "✅Nano for $TYPE build completed successfully in $((DIFF / 60)) minute(s) and $((DIFF % 60)) seconds."
		  echo "Zipping Files.."
		  mv $KERNEL_PATH/$OUT_PATH/Image.gz-dtb anykernel2/Image.gz-dtb
		  mv $KERNEL_PATH/anykernel2/Image.gz-dtb $KERNEL_PATH/anykernel2/zImage
		  cd $KERNEL_PATH/anykernel2
		     zip -r $FILE_NAME * -x .git README.md 
		     scp $FILE_NAME pshreejoy15@frs.sourceforge.net:/home/frs/p/nano-releases/$TYPE
		     rm -rf zImage
		     mv $FILE_NAME $KERNEL_PATH
		  cd ..
		  curl --data '{"chat_id":"'"$channel_id"'", "text":"🔥 *Releasing New Build* 🔥\n\n📱Release for *$TYPE*\n\n⏱ *Timestamp* :- $(date)\n\n🔹 Download 🔹\n[$FILE_NAME]($LINK)", "parse_mode":"Markdown", "disable_web_page_preview":"yes" }' -H "Content-Type: application/json" -X POST https://api.telegram.org/bot$bottoken/sendMessage
		  curl --data '{"chat_id":"'"$channel_id"'", "sticker":"CAADBQADHQADW31iJK_MskdmvJABAg" }' -H "Content-Type: application/json" -X POST https://api.telegram.org/bot$bottoken/sendSticker
                  rm -rf $KERNEL_PATH/anykernel
		  rm -rf $KERNEL_PATH/out
	   else 
		  sendTG "❌ Nano for $TYPE build failed in $((DIFF / 60)) minute(s) and $((DIFF % 60)) seconds"
		  exit
	   fi	
  done
}

function changelogs() {
   git clone https://github.com/nano-kernel-project/Nano_OTA_changelogs $KERNEL_PATH/changelogs
   export old_hash=$(jq -r '.commit_hash' $KERNEL_PATH/changelogs/information.json)
   if [ -z "$old_hash" ]; then 
      echo "Old hash doesent exist" 
      export new_hash=$(git log --format="%H" -n 1)
      jq --arg new_hash "$new_hash" '.commit_hash = $new_hash' $KERNEL_PATH/changelogs/information.json > $KERNEL_PATH/changelogs/information1.json
      rm -rf $KERNEL_PATH/changelogs/information.json
      mv $KERNEL_PATH/changelogs/information1.json $KERNEL_PATH/changelogs/information.json
   else
      export new_hash=$(git log --format="%H" -n 1)
      export commit_range="${old_hash}..${new_hash}"
      export commit_log="$(git log --format='%s (by %cn)' $commit_range)"
      echo " " >> $KERNEL_PATH/changelogs/README.md
      echo " " >> $KERNEL_PATH/extras/changelogs/README.md
      echo "Date - $(date)" >> $KERNEL_PATH/changelogs/README.md
      echo " " >> $KERNEL_PATH/changelogs/README.md
      printf '%s\n' "$commit_log" | while IFS= read -r line
      do
         echo "* ${line}" >> $KERNEL_PATH/changelogs/README.md
      done
      jq --arg new_hash "$new_hash" '.commit_hash = $new_hash' $KERNEL_PATH/changelogs/information.json > $KERNEL_PATH/changelogs/information1.json
      rm -rf $KERNEL_PATH/changelogs/information.json
      mv $KERNEL_PATH/changelogs/information1.json $KERNEL_PATH/changelogs/information.json
      ota
   fi
}

function ota() {
   export new_name="Nano Kernel V$NUM"
   export new_ver=$NUM
   rm -rf $KERNEL_PATH/changelogs/api.json
   echo "{\n   \"name\": \"$new_name\",\n   \"ver\": $new_ver,\n   \"url\": \"$LINK_AOSP\"\n   \"miui_url\": \"$LINK_MIUI\"\n}" > $KERNEL_PATH/changelogs/api.json
   cd $KERNEL_PATH/changelogs
      git add README.md information.json api.json
      git -c "user.name=shreejoy" -c "user.email=pshreejoy15@gmail.com" commit -m "OTA : $(date)"
      git push -q https://${GITHUB_AUTH_TOKEN}@github.com/nano-kernel-project/Nano_Extras HEAD:master
   cd ..
}
  
checking 
exports
clone 
build
changelogs
