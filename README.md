# pcf-usage

The goal is to collect information from a PCF foundation and assess the value by leveraging the 5s framework (Speed, Scalability, Stability, Security and Saving) and align with business outcomes (developer productivity, Operational Efficiency, Day 2 Ops, Infrastructure Savings, Innovation, Cloud first).

We have 2 components:
* pcfusage.sh - script to capture foundation information into a json file
* [jupyter notebook](https://jupyter-notebook.readthedocs.io/en/stable/) - to help analyse the data

## Running the script
The first step is running an script that uses the [CF API](https://apidocs.cloudfoundry.org/2.4.0/) to collect data in a json format. The scripts uses the _cf curl_ command and requires you be logged in as _admin_. The script uses [jq](https://stedolan.github.io/jq/) to create an output that can be process by a jupyter notebook.

```bash
$ ./pcfusage.sh dev
```
> Where 'dev' is the prefix used to identified the foundation we'll be collecting data

In the _samples_ folder of this repo you can find an example output.

### API usage
Below is a list of current [CF API](https://apidocs.cloudfoundry.org/2.4.0/) used by the script. In some cases, we handle the paging for API calls that can return a large number of elements.

* /v2/apps
* /v2/users
* /v2/organizations
* /v2/spaces
* /v2/service_brokers
* /v2/service_instances

## Using the Jupyter Notebook
You'll need to install Jupyter and open the notebook in this repo. As per the instructions on [the Jupyter Notebook website](http://jupyter.readthedocs.io/en/latest/install.html), [Anaconda](https://www.anaconda.com/download) is the easiest way to install Jupyter Notebook, but any working installation with the proper Python libraries should work.  To open the Jupyter Notebook, run the following command from the root of this repository:

```bash
$ jupyter notebook pcf_foundation.ipynb
```
> This command should launch your web browser with the Jupyter Notebook loaded.

In the very first cell we load the file you captured with the _pcfusage.sh_ script. There is some basic metadata information that is not currently on the json file that you need to update. Below is an example loading the _borgescloud_foundation.json_ file. It's important to add the capture date so we can calculate the number of days since the application was last updated and the information on the DIEGO CELLS we use for calculating infrastructure utilization.

```
file = "/Users/mborges/Tools/PCF/scripts/borgescloud_foundation.json"
capture_date = datetime.datetime(2018, 6, 26, 0, 0)
diego_cell = {"number_of": 4, "vcpu": 4, "ram_gb": 32, "disk_gb": 32 }
```

In the first cell we create the dataframes that are used in the following cells. Each cell tries to look at the data from the 5s framework. 

