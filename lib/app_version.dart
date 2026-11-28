import 'package:flutter/material.dart';

const toyTownVersion = '1.0.19';

void showToyTownVersion(BuildContext context) => showAboutDialog(
  context: context,
  useRootNavigator: false,
  applicationName: 'ToyTown',
  applicationVersion: '$toyTownVersion · збірка 29',
  applicationIcon: const Icon(Icons.toys, size: 40),
);
