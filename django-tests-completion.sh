#/!bin/bash

# Global vars
apps=()
apps_paths=()
test_cases=()
test_methods=()
last_parsed_app=""

function add_test_methods(){		
	if [ "${tests}" ]; then
		# Save all the test methods for this test case into a joined string
		# and add it to test_methods array
		test_methods+=("${tests}")
		tests=()
	fi
}

function get_apps(){
	# Fetch the list of all the apps in the project
	# It disables the logging before doing any imports, so that it doesn't print any unwanted stuff in the shell
	if [ ! "${apps}" ]; then
		apps_temp=($(python -c 'import logging; logger = logging.getLogger(); logger.disabled = True; from settings import INSTALLED_APPS; print " ".join(INSTALLED_APPS)'))
		for app in "${apps_temp[@]}"; do
			# Build a list of apps with complete path to the app folder
			apps_paths+=("${app}")

			# Build a list of apps with only the app name
			app=(${app//./ })
			apps+=("${app[${#app[@]}-1]}")
		done
	fi
}

function parse_app_tests(){
	# Take an app name as argument and builds the test cases and test methods paths for that app
	app_name=$@

	# Find the path to the folder of the app
	app_folder_path=""
	
	apps_paths=(${apps_paths[@]})

	OIFS=$IFS; IFS=$" "
	for app_path in "${apps_paths[@]}"; do
		app_path_arr=(${app_path//./ })
		if [ "${app_path_arr[${#app_path_arr[@]}-1]}" == "${app_name}" ]; then
			app_folder_path="${app_path//.//}"
		fi
	done
	IFS=$OIFS

	# Bail out if the app doesn't exist
	if [ "${app_folder_path}" == "" ]; then
		return
	fi

	test_cases=()
	test_methods=()
	tests=""

	# Build a list of test files to parse for this particular app
	app_test_files=()
	if [ -f ${app_folder_path}/tests.py ]; then
		app_test_files+=("${app_folder_path}/tests.py")
	elif [ -d ${app_folder_path}/tests ]; then
		files=( $(find ${app_folder_path}/tests -name '*.py') )
		for file in ${files[@]}; do
			app_test_files+=("${file}")
		done
	fi

	# Get all the classes and test methods 
	OLDIFS=$IFS; IFS=$'\n'
	grep_output=( $(grep -E -oh "^class .+:|def test.+:" ${app_test_files[@]}) )
	IFS=$OLDIFS

	for line in "${grep_output[@]}"; do
		is_test_case=$(echo $line | grep -o '^class .\+:' | cut -d ' ' -f 2 | cut -d '(' -f 1)
		if [ ${is_test_case} ]; then

			# If it was an empty test case or not an actual test class then remove it
			if [ ${was_test_case} ]; then
				unset test_cases[${#test_cases[@]}-1]
			fi

			test_case=${is_test_case}
			test_cases+=("${app_name}.${test_case}")
			add_test_methods

		elif [ ${test_case} ]; then
			test_method=$(echo $line | grep -o 'def test.\+:' | cut -d ' ' -f 2 | cut -d '(' -f 1)
			tests+="${app_name}.${test_case}.${test_method} "
		fi
		was_test_case=${is_test_case}
	done

	add_test_methods
	unset IFS
}

function parse_app_if_necessary(){
	# Not parsing again if it was the last parsed app
	if [ ! "${last_parsed_app}" == "${test_path[0]}" ]; then
		parse_app_tests "${test_path[0]}"
		last_parsed_app="${test_path[0]}"
	fi
}

_django_test_completion(){
	local cur prev opts 
	COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    get_apps

    # Split the test path into an array with '.' as delimiter
	test_path=(${cur//./ })

	# Get the last character of the test path
	cur_last_char="$(echo "${cur}" | tail -c 2)"

	# If we're completing the test case or we need to list all test cases in an app
	if [[ ${#test_path[@]} -eq 2 && "${cur_last_char}" != "." ]] || [[ ${#test_path[@]} -eq 1 && "${cur_last_char}" == "." ]]; then
		
		parse_app_if_necessary

		# Complete with the test case names
		cases="${test_cases[@]}"
		COMPREPLY=( $(compgen -W "${cases}" -- ${cur}) )
		return 0

	# If we're completing the test methods or we need to list all test methods in a test case
	elif [ ${#test_path[@]} -eq 3 ] || [[ ${#test_path[@]} -eq 2 && "${cur_last_char}" == "." ]]; then

		parse_app_if_necessary

		# Complete with the test method names
		methods="${test_methods[@]}"
		COMPREPLY=( $(compgen -W "${methods}" -- ${cur}) )
		return
	fi

	opts_apps="${apps[@]}"
    COMPREPLY=($(compgen -W "${opts_apps}" -- ${cur}))
}

complete -F _django_test_completion -o default python manage.py test
complete -F _django_test_completion -o default python2.5 manage.py test
complete -F _django_test_completion -o default python2.7 manage.py test
