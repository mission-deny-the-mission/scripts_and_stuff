#!/bin/bash

# Function to check if a number is prime
is_prime() {
    local num=$1

    # Check for numbers less than 2, which are not prime
    [ $num -lt 2 ] && return 1

    # Check divisibility from 3 up to the square root of num
    for ((i=3; i*i<=num; i+=2)); do
        if [ $(echo "$num % $i" | bc -l) -eq 0 ]; then
            return 1
        fi
    done

    return 0
}

# Main script
read -p "Enter a number to check for prime numbers: " num

while [[ $num -ge 2 ]]; do
    if is_prime "$num"; then
        echo "$num"
    fi
    ((num--))
done

