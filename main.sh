
#!/usr/bin/env bash

. scripts/vars

printf "\n\n"
echo  "********* Starting training using Nematus ********\n\n"
start=`date +%s`
# training the models for ordering, structing, lexicalization and end-to-end
for task in end2end ordering structing lexicalization
  do
    echo "Task $task"
    task_dir=$root_dir/$task

    #echo "task=$task" > scripts/tmp

    for model in transformer rnn
      do
        echo "Running model=$model"p
        for run in 1 2 3
          do
            if [ ! -d "$task_dir/$model/$model$run" ];
            then
              mkdir $task_dir/$model/$model$run
            fi

            #echo "run=$run" >> scripts/tmp
            bash scripts/$model.sh
          done
      done
  done

echo "Starting to train NeuralREG"
# training NeuralREG for Referring Expression Generation
python3 reg/neuralreg.py --dynet-gpu
end=`date +%s`
runtime=$((end-start))
echo "Training models took $runtime"
