import 'package:flutter/material.dart';

const toyTownVersion = '1.0.15';

void showToyTownVersion(BuildContext context) => showAboutDialog(
  context: context,
  applicationName: 'ToyTown',
  applicationVersion: '$toyTownVersion · збірка 25',
  applicationIcon: const Icon(Icons.toys, size: 40),
);
