#!/bin/bash
set -x

SCALATEST_VERSION=3.0.5

# https://stackoverflow.com/a/246128
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

SPARK_HOME=${SPARK_HOME:-$HOME/gits/apache/spark}

# pre-requisite: `mvn package` has been run
SPARK_RAPIDS_HOME=${SPARK_RAPIDS_HOME:-$HOME/gits/NVIDIA/spark-rapids}

RAPIDS_SHELL_HOME=${RAPIDS_SHELL_HOME:-"$(dirname $(dirname $DIR))"}

SCALATEST_JARS=$(find ~/.m2 \
	-path \*/$SCALATEST_VERSION/\* -name \*scalatest\*jar -o \
	-path \*/$SCALATEST_VERSION/\* -name \*scalactic\*jar | tr -s "\n" ":")

RAPIDS_PLUGIN_JAR=$(find $SPARK_RAPIDS_HOME -regex ".*/rapids-4-spark_2.12-[0-9]+\.[0-9]+\.[0-9]+\(-SNAPSHOT\)?.jar")
CUDF_JAR=$(find $SPARK_RAPIDS_HOME -name cudf\*jar)
RAPIDS_CLASSPATH="$RAPIDS_PLUGIN_JAR:$CUDF_JAR:$SCALATEST_JARS"

FINAL_JAVA_OPTS=(
	"-ea"
	"-Duser.timezone=UTC"
	"-Dlog4j.debug=true"
	"-Dlog4j.configuration=file:${RAPIDS_SHELL_HOME}/src/conf/log4j.properties"
	"$RAPIDS_JAVA_OPTS"
)

SPARK_SHELL=${SPARK_SHELL:-spark-shell}

export IT_ROOT=${IT_ROOT:-"$SPARK_RAPIDS_HOME/integration_tests"}

# for all pyspark drivers
export PYTHONPATH="$PYTHONPATH:$IT_ROOT/src/main/python"

export LD_LIBRARY_PATH="$CONDA_PREFIX/lib"

case "$SPARK_SHELL" in

	"spark-shell")
		SPARK_SHELL_RC="-I $RAPIDS_SHELL_HOME/src/scala/rapids.scala"
		;;

	"pyspark")
		;;

	"jupyter")
		export PYSPARK_DRIVER_PYTHON="$SPARK_SHELL"
		export PYSPARK_DRIVER_PYTHON_OPTS="notebook"
		SPARK_SHELL="pyspark"
		;;

	"jupyter-lab")
		export PYSPARK_DRIVER_PYTHON="$SPARK_SHELL"
		SPARK_SHELL="pyspark"
		;;

	*)
		echo -n "Unknown spark-rapids driver!"
		;;
esac

${SPARK_HOME}/bin/${SPARK_SHELL} \
	${SPARK_SHELL_RC} \
	--master 'local-cluster[2,2,4096]' \
	--driver-memory 4g \
	--driver-java-options "${FINAL_JAVA_OPTS[*]}" \
	--driver-class-path "$RAPIDS_CLASSPATH" \
	--conf spark.executor.extraJavaOptions="${FINAL_JAVA_OPTS[*]}" \
	--conf spark.executor.extraClassPath="$RAPIDS_CLASSPATH" \
	--conf spark.plugins=com.nvidia.spark.SQLPlugin \
	--conf spark.sql.extensions=com.nvidia.spark.rapids.SQLExecPlugin,com.nvidia.spark.udf.Plugin \
	--conf spark.rapids.memory.gpu.debug=STDOUT \
	--conf spark.rapids.memory.gpu.allocFraction=0.45 \
	--conf spark.rapids.sql.enabled=true \
	--conf spark.rapids.sql.test.enabled=false \
	--conf spark.rapids.sql.test.allowedNonGpu=org.apache.spark.sql.execution.LeafExecNode \
	--conf spark.rapids.sql.explain=ALL \
	--conf spark.rapids.sql.exec.CollectLimitExec=true \
	"$@"
