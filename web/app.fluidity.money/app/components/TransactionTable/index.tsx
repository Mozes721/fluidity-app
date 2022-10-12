import type { Chain } from "~/util/chainUtils/chains";
import type { IRow } from "~/components/Table";

import { Text, trimAddress } from "@fluidity-money/surfing";

import { getAddressExplorerLink } from "~/util";

import { isYesterday, isToday, formatDistanceToNow, format } from "date-fns";

import { motion } from "framer-motion";

import { Table } from "~/components";
import { Link } from "@remix-run/react";

type Transaction = {
  sender: string;
  receiver: string;
  timestamp: number;
  value: number;
  currency: string;
};

const ActivityLabel = (activity: Transaction, address: string) => {
  const { sender, currency } = activity;
  return sender === address ? `Sent ${currency}` : `Received ${currency}`;
};

const TimeLabel = (timestamp: number) => {
  const isTransactionToday = isToday(timestamp * 1000);
  const isTransactionYesterday = isYesterday(timestamp * 1000);

  if (isTransactionToday)
    return formatDistanceToNow(timestamp * 1000, {
      addSuffix: true,
    });

  if (isTransactionYesterday)
    return `Yesterday ${format(timestamp * 1000, "h:mmaaa")}`;

  return format(timestamp * 1000, "dd.MM.yy h:mmaaa");
};

const TransactionRow = (chain: Chain, address: string): IRow<Transaction> =>
  function Row({ data, index }: { data: Transaction; index: number }) {
    const { sender, receiver, timestamp, value, currency } = data;

    const txAddress = sender === address ? receiver : sender;

    return (
      <motion.tr
        key={`${timestamp}-${index}`}
        variants={{
          enter: { opacity: [0, 1] },
          ready: { opacity: 1 },
          exit: { opacity: 0 },
          transitioning: {
            opacity: [0.75, 1, 0.75],
            transition: { duration: 1.5, repeat: Infinity },
          },
        }}
      >
        {/* Activity */}
        <td>
          <a>
            <Text>
              {currency} {ActivityLabel(data, address)}
            </Text>
          </a>
        </td>

        {/* Value */}
        <td>
          <Text>
            {value.toLocaleString("en-US", {
              style: "currency",
              currency: "USD",
            })}
          </Text>
        </td>

        {/* Reward */}
        <td>
          <Text prominent={true}>-</Text>
        </td>

        {/* Account */}
        <td>
          <Link to={getAddressExplorerLink(chain, txAddress)}>
            <Text>{trimAddress(txAddress)}</Text>
          </Link>
        </td>

        {/* Time */}
        <td>{TimeLabel(timestamp)}</td>
      </motion.tr>
    );
  };

type ITransactionTable = {
  page: number;
  count: number;
  transactions: Transaction[];
  chain: Chain;
  address: string;
};

const TransactionTable = ({
  page,
  count,
  transactions,
  chain,
  address,
}: ITransactionTable) => {
  const txTableColumns = [
    {
      name: "ACTIVITY",
    },
    {
      name: "VALUE",
    },
    {
      name: "REWARD",
    },
    {
      name: "ACCOUNT",
    },
    {
      name: "TIME",
      alignRight: true,
    },
  ];

  return (
    <Table
      itemName="transactions"
      headings={txTableColumns}
      pagination={{
        page: page,
        rowsPerPage: 12,
      }}
      count={count}
      data={transactions}
      renderRow={TransactionRow(chain, address)}
    />
  );
};

export default TransactionTable;