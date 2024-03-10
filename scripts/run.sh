cuda_num=8
temperature=0.7
iter_num=0
sample_num=1
is_englishs=(True False)
tensor_parallel=2

method=few_shot_cot

# Array of models
model_types=(vicuna-13b)

# Array of datasets
datasets=(plan tool_use_awareness tool_selection_harder tool_creation_awareness_harder tool_creation arguments_filling)

for is_english in "${is_englishs[@]}"; do
    for model_type in "${model_types[@]}"; do
        save_name=${model_type}
        # Loop over each dataset in the array
        for dataset in "${datasets[@]}"; do
            if [ "$is_english" == "True" ]; then
                output_dir="generate_result/${method}/english/${dataset}/${save_name}"
                log_dir="log/${method}/english/${dataset}/${save_name}"
            else
                output_dir="generate_result/${method}/chinese/${dataset}/${save_name}"
                log_dir="log/${method}/chinese/${dataset}/${save_name}"
            fi

            mkdir -p "${output_dir}"
            mkdir -p "${log_dir}"

            for cd in $(seq 0 $((cuda_num/8 - 1))); do
                for ind in $(seq 0 $tensor_parallel $((cuda_num - 1))); do
                    gpu_indices=$(seq -s ',' $ind $((ind + tensor_parallel - 1)))
                    CUDA_VISIBLE_DEVICES=$gpu_indices nohup python inference_ultraltool.py --dataset ${dataset} --english ${is_english} --model_type ${model_type} --method ${method} --temperature ${temperature} --iter_num ${iter_num} --iter_max_new_tokens 512 --sample_num ${sample_num} --tensor_parallel ${tensor_parallel} --cuda_start $((cd * tensor_parallel)) --cuda_ind ${ind} --cuda_num ${cuda_num} --load_in_8bit False --output_dir ${output_dir} 2>&1 > "${log_dir}/${cd}-${ind}.log" &
                done
            done
                   
                 # Wait for GPUs to be free
                memory_threshold=500 # Memory threshold in MiB
                sleep 120 # Initial sleep for 3 minutes

                while true; do
                    all_gpus_free=true

                    for gpu_id in {0..7}; do
                        memory_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i $gpu_id)

                        if [ "$memory_used" -le "$memory_threshold" ]; then
                            echo "GPU $gpu_id is free."
                        else
                            echo "GPU $gpu_id is still in use. Memory used: $memory_used MiB"
                            all_gpus_free=false
                            break
                        fi
                    done

                    if $all_gpus_free; then
                        echo "All GPUs are free. Proceeding to next process..."
                        break
                    else
                        echo "Waiting for all GPUs to be free..."
                        sleep 10 # Wait for 10 seconds before checking again
                    fi
                done

                sleep 180 # Additional sleep for 6 minutes after all GPUs are free
        done
    done
done
