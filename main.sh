
#!/usr/bin/env bash

. scripts/vars

if [ ! -d "$root_dir" ];
then
  mkdir $root_dir
fi

base_dir=/scratch/hpc-prf-nina/maqbool/DeepNLG

# preprocessing
start=`date +%s`
for task in end2end ordering structing lexicalization
  do
    echo "Task $task"
    task_dir=$root_dir/$task
    echo "checking if $task directory exist in results folder.."
    if [ ! -d "$task_dir" ];
    then
      mkdir $task_dir
    fi


    #echo "task=$task" > scripts/tmp
    #echo "task_dir=$task_dir" >> scripts/tmp

    python3 maqtest/tester.py

    echo "starting pre processing for $task"
    # preprocessing
    if [ "$task" = "lexicalization" ] || [ "$task" = "end2end" ];
    then
      printf "\n\n"
      echo ">> $task"
      python3 $task/preprocess.py $corpus_dir $task_dir $stanford_path
      echo "starting pre processing_txt.sh"
      bash scripts/preprocess_txt.sh
    else
      printf "\n\n"
      echo "<< $task"
      python3 $task/preprocess.py $corpus_dir $task_dir
      echo "starting pre processing.sh"
      bash scripts/preprocess.sh
    fi
    echo "Done pre preprocessing for $task"
  done

if [ ! -d "$root_dir/reg" ];
then
  mkdir $root_dir/reg
fi
printf "\n\n"
echo "Starting pre processing for REG"
python3 reg/preprocess.py $corpus_dir $root_dir/reg $stanford_path
echo "Done pre procssing for REG"
end=`date +%s`
runtime=$((end-start))
echo "Pre processing took $runtime"
