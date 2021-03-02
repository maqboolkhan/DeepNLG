#!/usr/bin/env bash

. scripts/vars

if [ ! -d "$root_dir" ];
then
  mkdir $root_dir
fi

base_dir=/scratch/hpc-prf-nina/maqbool/DeepNLG

# preprocessing
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

    python3 $base_dir/tester.py

    echo "starting pre processing for $task"
    # preprocessing
    if [ "$task" = "lexicalization" ] || [ "$task" = "end2end" ];
    then
      echo ">> $task"
      python3 $base_dir/$task/preprocess.py $corpus_dir $task_dir $stanford_path
      echo "starting pre processing_txt.sh"
      ./scripts/preprocess_txt.sh
    else
      echp "<< $task"
      python3 $base_dir/$task/preprocess.py $corpus_dir $task_dir
      echo "starting pre processing.sh"
      ./scripts/preprocess.sh
    fi
    echo "Done pre preprocessing for $task"
  done

if [ ! -d "$root_dir/reg" ];
then
  mkdir $root_dir/reg
fi
echo "\nStarting pre processing for REG"
python3 reg/preprocess.py $corpus_dir $root_dir/reg $stanford_path
echo "Done pre procssing for REG"

echo  "\n\n********* Starting training using Nematus ********\n\n"
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
            ./scripts/$model.sh
          done
      done
  done

echo "Starting to train NeuralREG"
# training NeuralREG for Referring Expression Generation
python3 reg/neuralreg.py --dynet-gpu

echo "\n\n*************Starting Baselines Evaluatio\n\nn"
root_baseline=$root_dir/baselines

if [ ! -d "$root_baseline" ];
then
  mkdir $root_baseline
fi

for task in ordering structing lexicalization
  echo "Baseline for $task"
  do
    root_task=$root_baseline/$task
    if [ ! -d "$root_task" ];
    then
      mkdir $root_task
    fi

    for baseline in rand major
      do
        for set in dev test
          do
            cp $root_dir/$task/data/$set.$eval $root_task
            python3 $task/$baseline.py $root_task/$set.$eval $root_task/$baseline.$set $root_dir/$task/data/train.json

            ref=$root_dir/$task/data/references/$set.$trg
            refs=$ref"1 "$ref"2 "$ref"3 "$ref"4 "$ref"5"

            echo $task "-" $set "-" $baseline
            # evaluate with detokenized BLEU (same as mteval-v13a.pl)
            if [ "$task" = "lexicalization" ];
            then
              $nematus_home/data/multi-bleu-detok.perl $refs < $root_task/$baseline.$set
            else
              script_dir=`dirname $0`/scripts
              python3 $script_dir/accuracy.py $ref $root_task/$baseline.$set
            fi
          done
      done
  done

echo "\n\n********** Starting Models Evaluation *************"
# Evaluation of the approaches for Discourse Ordering, text Structuring, Lexicalization, REG and End-to-End
for task in ordering structing lexicalization end2end
  do
    echo "Task $task"

    task_dir=$root_dir/$task
    echo "task_dir=$task_dir" 
    for model in transformer rnn
      do
        echo "model=$model"
        # evaluating the model
        for set in dev test
          do
            echo "task=$task" > scripts/tmp
            echo "task_dir=$task_dir" >> scripts/tmp
            echo "model=$model" >> scripts/tmp
            echo "test_prefix=$set" >> scripts/tmp
            ./scripts/evaluate.sh
          done
      done
  done

echo "\n\n********* Starting Baseline Pipeline ***********"
root_pipeline=$root_dir/pipeline

if [ ! -d "$root_pipeline" ];
then
  mkdir $root_pipeline
fi
echo "root_pipeline=$root_pipeline" > scripts/tmp

for baseline in rand major
  do
    pipeline_dir=$root_pipeline/$baseline
    if [ ! -d "$pipeline_dir" ];
    then
      mkdir $pipeline_dir
    fi
    echo "pipeline_dir=$pipeline_dir" > scripts/tmp


    for set in dev test
      do
        cp $root_dir/end2end/data/$set.$eval $pipeline_dir
        task=end2end
        #echo "task=$task" > scripts/tmp

        task_dir=$root_dir/$task
        #echo "task_dir=$task_dir" >> scripts/tmp

        # ordering
	echo "Starting Ordering for $set set"
        python3 ordering/$baseline.py $pipeline_dir/$set.$eval $pipeline_dir/$set.ordering $root_dir/ordering/data/train.json
        python3 mapping.py $pipeline_dir/$set.$eval $pipeline_dir/$set.ordering ordering $pipeline_dir/$set.ordering.mapped
        # structing
	echo "Starting Structring for $set set"
        python3 structing/$baseline.py $pipeline_dir/$set.ordering.mapped $pipeline_dir/$set.structing $root_dir/structing/data/train.json
        python3 mapping.py $pipeline_dir/$set.$eval $pipeline_dir/$set.structing structing $pipeline_dir/$set.structing.mapped
        # lexicalization
	echo "Starting lexicalization for $set set"
        python3 lexicalization/$baseline.py $pipeline_dir/$set.structing.mapped $pipeline_dir/$set.lex $root_dir/structing/data/train.json
        # referring expression generation
	echo "Starting REG for $set set"
        python3 reg/generate.py $pipeline_dir/$set.lex $pipeline_dir/$set.ordering.mapped $pipeline_dir/$set.reg baseline path
        # textual realization
	echo "Starting realization for $set set"
        python3 realization.py $pipeline_dir/$set.reg $pipeline_dir/$set.realized $root_dir/lexicalization/surfacevocab.json

        cat $pipeline_dir/$set.realized | \
        sed -r 's/\@\@ //g' |
        $moses_scripts/tokenizer/normalize-punctuation.perl -l $lng > $pipeline_dir/$set.out

        cat $pipeline_dir/$set.realized | \
        sed -r 's/\@\@ //g' |
        $moses_scripts/recaser/detruecase.perl |
        $moses_scripts/tokenizer/normalize-punctuation.perl -l $lng |
        $moses_scripts/tokenizer/detokenizer.perl -l $lng > $pipeline_dir/$set.out.postprocessed

        data_dir=$task_dir/data/references
        ref=$data_dir/$set.$trg
        refs=$ref"1 "$ref"2 "$ref"3 "$ref"4 "$ref"5"
        $nematus_home/data/multi-bleu-detok.perl $refs < $pipeline_dir/$set.out
      done
  done

echo "Pipeline Models"
echo "root_pipeline=$root_pipeline" > scripts/tmp

for model in transformer rnn
  do
    pipeline_dir=$root_pipeline/$model
    if [ ! -d "$pipeline_dir" ];
    then
      mkdir $pipeline_dir
    fi

    for set in dev test
      do
        cp $root_dir/end2end/data/$set.$eval $pipeline_dir

        # ordering
        task=ordering
        echo "pipeline_dir=$pipeline_dir" > scripts/tmp
        task_dir=$root_dir/$task
        echo "task_dir=$task_dir" >> scripts/tmp
        echo "model=$model" >> scripts/tmp
        echo "input=$set.$eval" >> scripts/tmp
        echo "output=$set.ordering" >> scripts/tmp
        ./scripts/pipeline.sh
        python3 mapping.py $pipeline_dir/$set.$eval $pipeline_dir/$set.ordering.postprocessed ordering $pipeline_dir/$set.ordering.mapped

        # structuring
        task=structing
        echo "pipeline_dir=$pipeline_dir" > scripts/tmp
        task_dir=$root_dir/$task
        echo "task_dir=$task_dir" >> scripts/tmp
        echo "model=$model" >> scripts/tmp
        echo "input=$set.ordering.mapped" >> scripts/tmp
        echo "output=$set.structing" >> scripts/tmp
        ./scripts/pipeline.sh
        python3 mapping.py $pipeline_dir/$set.$eval $pipeline_dir/$set.structing.postprocessed structing $pipeline_dir/$set.structing.mapped

        # lexicalization
        task=lexicalization
        echo "pipeline_dir=$pipeline_dir" > scripts/tmp
        task_dir=$root_dir/$task
        echo "task_dir=$task_dir" >> scripts/tmp
        echo "model=$model" >> scripts/tmp
        echo "input=$set.structing.mapped" >> scripts/tmp
        echo "output=$set.lex" >> scripts/tmp
        ./scripts/pipeline.sh
        python3 mapping.py $pipeline_dir/$set.ordering.mapped $pipeline_dir/$set.lex.postprocessed lexicalization $pipeline_dir/$set.lex.mapped

        # reg
        python3 reg/generate.py $pipeline_dir/$set.lex.postprocessed $pipeline_dir/$set.ordering.mapped $pipeline_dir/$set.reg neuralreg $root_dir/reg/model1.dy

        # textual realization
        python3 realization.py $pipeline_dir/$set.reg $pipeline_dir/$set.realized $root_dir/lexicalization/surfacevocab.json
        cat $pipeline_dir/$set.realized | \
        sed -r 's/\@\@ //g' |
        $moses_scripts/tokenizer/normalize-punctuation.perl -l $lng > $pipeline_dir/$set.out

        cat $pipeline_dir/$set.realized | \
        sed -r 's/\@\@ //g' |
        $moses_scripts/recaser/detruecase.perl |
        $moses_scripts/tokenizer/normalize-punctuation.perl -l $lng |
        $moses_scripts/tokenizer/detokenizer.perl -l $lng > $pipeline_dir/$set.out.postprocessed

        data_dir=$root_dir/end2end/data/references
        ref=$data_dir/$set.$trg
        refs=$ref"1 "$ref"2 "$ref"3 "$ref"4 "$ref"5"
        $nematus_home/data/multi-bleu-detok.perl $refs < $pipeline_dir/$set.out.postprocessed
      done
  done
